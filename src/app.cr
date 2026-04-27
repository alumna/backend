require "http/server"

module Alumna
  class App
    # before and after rules can be applied at the app (global) level
    include Ruleable

    alias TrustedProxies = Bool | Array(String) | Nil

    getter serializer : Http::Serializer
    getter services : Hash(String, Service)
    getter trusted_proxies : TrustedProxies

    # Defaults
    property max_body_size : Int64 = 1_048_576 # 1 MB default

    def initialize(@serializer : Http::Serializer = Http::JsonSerializer.new, @trusted_proxies : TrustedProxies = nil)
      @services = {} of String => Service
    end

    def use(path : String, service : Service) : self
      @services[path] = service
      self
    end

    # central dispatch that wraps service dispatch
    def dispatch(service : Service, ctx : RuleContext) : RuleContext
      # 1. app before
      ctx.phase = RulePhase::Before
      Orchestrator.run(collect_rules(ctx.method, RulePhase::Before), ctx)
      return error_rules(ctx) if ctx.error

      # 2. service (includes its own before/after)
      unless ctx.result_set?
        service.dispatch(ctx)
        return error_rules(ctx) if ctx.error
      end

      # 3. app after
      ctx.phase = RulePhase::After
      Orchestrator.run(collect_rules(ctx.method, RulePhase::After), ctx)
      ctx
    end

    def listen(port : Int32 = 3000)
      router = Http::Router.new(self, @trusted_proxies)
      server = HTTP::Server.new { |ctx| router.handle(ctx) }
      puts "Listening on http://0.0.0.0:#{port}"
      server.listen("0.0.0.0", port)
    end

    private def error_rules(ctx : RuleContext)
      ctx.phase = RulePhase::Error
      Orchestrator.run(collect_rules(ctx.method, RulePhase::Error), ctx)
      ctx
    end
  end
end
