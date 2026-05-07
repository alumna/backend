require "http/server"
require "./router/*"
require "./serializers"

module Alumna
  module Http
    class Router
      enum TrustMode
        None
        All
        List
      end

      @services : Hash(String, Service)
      @trust_mode : TrustMode
      @trusted_set : TrustedProxySet?

      def initialize(@app : App, trusted_proxies : App::TrustedProxies = nil)
        @services = @app.services
        @trust_mode, @trusted_set = case trusted_proxies
                                    when nil, false then {TrustMode::None, nil}
                                    when true       then {TrustMode::All, nil}
                                    when Array      then {TrustMode::List, TrustedProxySet.new(trusted_proxies)}
                                    else                 {TrustMode::None, nil}
                                    end
      end

      def handle(http_ctx : HTTP::Server::Context) : Nil
        request = http_ctx.request
        response = http_ctx.response

        input_serializer = resolve_input_serializer(request) || @app.serializer
        output_serializer = resolve_output_serializer(request) || input_serializer
        response.content_type = output_serializer.content_type

        begin
          data = parse_body(request, input_serializer)
        rescue ex : ServiceError
          Responder.write_error(response, ex, output_serializer)
          return
        end

        match = resolve_service(request.path)
        unless match
          Responder.write_error(response, ServiceError.not_found("No service at #{request.path}"), output_serializer)
          return
        end

        service, id = match
        method = resolve_method(request.method, id)
        unless method
          Responder.write_error(response, ServiceError.new("Method not allowed", 405), output_serializer)
          return
        end

        ctx = RuleContext.new(
          app: @app,
          service: service,
          path: service.path,
          method: method,
          phase: RulePhase::Before,
          http_method: request.method,
          remote_ip: remote_ip(http_ctx),
          params: ParamsView.new(request.query_params),
          headers: HeadersView.new(request.headers),
          id: id,
          data: data
        )

        ctx.app.dispatch(service, ctx)
        Responder.write(response, ctx, output_serializer)
      end

      private def resolve_service(path : String) : {Service, String?}?
        # treat /items and /items/ as identical
        path = path == "/" ? path : path.chomp('/')

        # 1) exact match – find/create – single hash lookup, no allocations
        if service = @services[path]?
          return {service, nil}
        end

        # 2) must be /base/id – find the first '/' after the leading one
        # index('/', 1) is cheaper than rindex and tells us the base length
        sep = path.index('/', 1)
        return nil unless sep

        # 3) reject /base/id/extra in the same scan – no id.includes?('/')
        return nil if path.index('/', sep + 1)

        # 4) only now allocate the base string and do the second hash lookup
        base = path[0...sep]
        service = @services[base]?
        return nil unless service

        # 5) id is the tail – we already know it's non-empty and has no '/'
        id = path[sep + 1..]
        return nil if id.empty?
        {service, id}
      end

      private def resolve_method(http_verb : String, id : String?) : ServiceMethod?
        has_id = !id.nil?
        case {http_verb, has_id}
        when {"GET", false}   then ServiceMethod::Find
        when {"GET", true}    then ServiceMethod::Get
        when {"POST", false}  then ServiceMethod::Create
        when {"PUT", true}    then ServiceMethod::Update
        when {"PATCH", true}  then ServiceMethod::Patch
        when {"DELETE", true} then ServiceMethod::Remove
        when {"OPTIONS", _}   then ServiceMethod::Options
        else                       nil
        end
      end

      private def resolve_input_serializer(request : HTTP::Request) : Serializer?
        Serializers.from_content_type?(request.headers["content-type"]?)
      end

      private def resolve_output_serializer(request : HTTP::Request) : Serializer?
        Serializers.from_accept?(request.headers["accept"]?)
      end

      private def parse_body(request : HTTP::Request, serializer : Serializer) : Hash(String, AnyData)
        body = request.body
        return {} of String => AnyData if body.nil?

        # empty body → {} (preserves the existing spec)
        if (len = request.content_length) && len == 0
          return {} of String => AnyData
        end

        if limit = @app.max_body_size
          if (len = request.content_length) && len > limit
            raise ServiceError.new("Payload Too Large", 413)
          end
          body = LimitedIO.new(body, limit)
        end

        serializer.decode(body)
      rescue IO::Error
        raise ServiceError.new("Payload Too Large", 413)
      end

      private def remote_ip(ctx : HTTP::Server::Context) : String
        case @trust_mode
        in TrustMode::None then direct_ip(ctx)
        in TrustMode::All  then extract_ip(ctx, nil, true)
        in TrustMode::List then extract_ip(ctx, @trusted_set, false)
        end
      end

      private def direct_ip(ctx : HTTP::Server::Context) : String
        addr = ctx.request.remote_address
        addr.is_a?(Socket::IPAddress) ? addr.address : "-"
      end

      private def extract_ip(ctx : HTTP::Server::Context, trusted_set : TrustedProxySet?, trust_all : Bool) : String
        remote = direct_ip(ctx)
        return remote unless trust_all || trusted_set.try(&.trusted?(remote))

        parse_forwarded(ctx, remote, trusted_set, trust_all) ||
          parse_xff(ctx, remote, trusted_set, trust_all) ||
          parse_x_real_ip(ctx) || remote
      end

      private def parse_forwarded(ctx : HTTP::Server::Context, remote_ip : String, trusted_set : TrustedProxySet?, trust_all : Bool) : String?
        fwd = ctx.request.headers["Forwarded"]?
        return nil unless fwd

        # Guard against absurdly long headers – cheap DoS protection
        return nil if fwd.bytesize > 2_048

        ips = [] of String

        # RFC 7239: Forwarded: for=1.2.3.4;proto=http, for="[2001:db8::1]"
        fwd.split(',') do |segment|
          segment.split(';') do |pair|
            pair = pair.lstrip
            next unless pair.size > 4

            # case-insensitive "for=" without allocating a downcased copy
            next unless pair[0].downcase == 'f' &&
                        pair[1].downcase == 'o' &&
                        pair[2].downcase == 'r' &&
                        pair[3] == '='

            val = pair[4..].strip

            # strip optional quotes: for="1.2.3.4:1234" or for="[::1]:1234"
            if val.size >= 2 && val.starts_with?('"') && val.ends_with?('"')
              val = val[1...-1]
            end

            ip = extract_ip_from_forwarded(val)
            ips << ip if Socket::IPAddress.valid?(ip)
          end
        end

        return nil if ips.empty?

        # Append the direct remote so the full proxy chain is walked,
        # mirroring parse_xff (the Forwarded header does not include the
        # last hop's own IP, just as XFF does not).
        ips << remote_ip

        # Walk right-to-left, skipping trusted proxies – same logic as parse_xff.
        # ips.first is the original client (leftmost for= entry per RFC 7239 §4).
        ips.reverse_each do |ip|
          next unless Socket::IPAddress.valid?(ip)
          return trust_all ? ips.first : ip unless trusted_set.try(&.trusted?(ip))
        end
        nil
      end

      private def extract_ip_from_forwarded(val : String) : String
        # IPv6 in brackets with optional port: [::1] or [::1]:1234
        if val.starts_with?('[')
          if close = val.index(']')
            return val[1...close]
          end
        end

        # IPv4 with optional port: 1.2.3.4 or 1.2.3.4:1234
        # The !possible.includes?(':') guard prevents accidentally truncating
        # a bare IPv6 address (no brackets) at its last colon.
        if colon = val.rindex(':')
          possible = val[0...colon]
          if !possible.includes?(':') && Socket::IPAddress.valid?(possible)
            return possible
          end
        end

        val
      end

      private def parse_xff(ctx, remote_ip, trusted_set, trust_all) : String?
        xff = ctx.request.headers["X-Forwarded-For"]?
        return nil unless xff

        ips = [] of String
        xff.split(',') do |part|
          s = part.strip
          ips << s unless s.empty?
        end
        ips << remote_ip

        ips.reverse_each do |ip|
          next unless Socket::IPAddress.valid?(ip)
          return trust_all ? ips.first : ip unless trusted_set.try(&.trusted?(ip))
        end
        nil
      end

      private def parse_x_real_ip(ctx) : String?
        ip = ctx.request.headers["X-Real-IP"]?.try(&.strip)
        ip if ip && Socket::IPAddress.valid?(ip)
      end
    end
  end
end
