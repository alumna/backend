require "http/cookie"

module Alumna
  # Binds a SessionStore to cookie flags. Keep one instance for the rule and
  # for start/stop/rotate so the cookie name and flags stay in sync.
  #
  #   sessions = Alumna::Session.new(Alumna::MemorySessionStore.new(ttl: 24.hours))
  #   app.before sessions.rule
  #   sessions.start(ctx, Alumna.hash(user_id: id))
  class Session
    DEFAULT_COOKIE    = "alumna.sid"
    DEFAULT_STORE_KEY = "session"
    DEFAULT_SKIP      = ["internal", "local"]

    getter store : SessionStore
    getter cookie : String
    getter store_key : String
    @same_site : HTTP::Cookie::SameSite

    def initialize(
      @store : SessionStore,
      *,
      @cookie : String = DEFAULT_COOKIE,
      @store_key : String = DEFAULT_STORE_KEY,
      @required : Bool = true,
      @skip_providers : Array(String) = DEFAULT_SKIP,
      @http_only : Bool = true,
      @secure : Bool = false,
      same_site : Symbol = :lax,
      @path : String = "/",
      @domain : String? = nil,
    )
      raise ArgumentError.new("session cookie name must not be empty") if @cookie.empty?
      @same_site = self.class.parse_same_site(same_site)
      if @same_site.none? && !@secure
        raise ArgumentError.new("session same_site: :none requires secure: true")
      end
    end

    def self.parse_same_site(same_site : Symbol) : HTTP::Cookie::SameSite
      case same_site
      when :lax    then HTTP::Cookie::SameSite::Lax
      when :strict then HTTP::Cookie::SameSite::Strict
      when :none   then HTTP::Cookie::SameSite::None
      else
        raise ArgumentError.new("same_site must be :lax, :strict, or :none")
      end
    end

    def rule : Rule
      required = @required
      skip = @skip_providers
      cookie = @cookie
      store_key = @store_key
      store = @store

      Rule.new do |ctx|
        next nil if ctx.http_method == "OPTIONS"
        next nil if skip.includes?(ctx.provider)

        raw = ctx.headers["cookie"]?
        id = raw ? Http.cookie_value(raw, cookie) : nil
        if id.nil? || id.empty?
          next required ? ServiceError.unauthorized("Missing session") : nil
        end

        data = store.get(id)
        next ServiceError.unauthorized unless data

        ctx.store[store_key] = data
        nil
      end
    end

    def start(ctx : RuleContext, data : Hash(String, AnyData), ttl : Time::Span? = nil) : String
      span = ttl || @store.default_ttl
      id = @store.new_id
      @store.set(id, data, span)
      ctx.http.add_cookie(build_cookie(id, span))
      ctx.store[@store_key] = data
      id
    end

    def stop(ctx : RuleContext) : Nil
      if raw = ctx.headers["cookie"]?
        if id = Http.cookie_value(raw, @cookie)
          @store.delete(id) unless id.empty?
        end
      end
      ctx.http.add_cookie(build_cookie("", Time::Span.zero))
      ctx.store.delete(@store_key)
    end

    def rotate(ctx : RuleContext, data : Hash(String, AnyData), ttl : Time::Span? = nil) : String
      if raw = ctx.headers["cookie"]?
        if id = Http.cookie_value(raw, @cookie)
          @store.delete(id) unless id.empty?
        end
      end
      start(ctx, data, ttl)
    end

    # Class helpers use the default cookie name and flags. Prefer an instance
    # when you set cookie, secure, or same_site on the rule.
    def self.start(ctx : RuleContext, store : SessionStore, data : Hash(String, AnyData), ttl : Time::Span? = nil) : String
      new(store).start(ctx, data, ttl)
    end

    def self.stop(ctx : RuleContext, store : SessionStore) : Nil
      new(store).stop(ctx)
    end

    def self.rotate(ctx : RuleContext, store : SessionStore, data : Hash(String, AnyData), ttl : Time::Span? = nil) : String
      new(store).rotate(ctx, data, ttl)
    end

    private def build_cookie(value : String, ttl : Time::Span) : HTTP::Cookie
      max_age = ttl <= Time::Span.zero ? 0.seconds : ttl
      HTTP::Cookie.new(
        @cookie,
        value,
        path: @path,
        domain: @domain,
        max_age: max_age,
        secure: @secure,
        http_only: @http_only,
        samesite: @same_site,
      )
    end
  end
end
