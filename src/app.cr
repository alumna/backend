require "http/server"

module Alumna
  class App
    include Ruleable

    alias TrustedProxies = Bool | Array(String) | Nil

    getter serializer : Http::Serializer
    getter services : Hash(String, Service)

    property max_body_size : Int64 = 1_048_576

    def initialize(@serializer : Http::Serializer = Http::JsonSerializer.new)
      @services = {} of String => Service
      @pipelines_compiled = false
    end

    def use(path : String, service : Service) : self
      @services[path] = service
      self
    end

    private def compile_pipelines!
      return if @pipelines_compiled
      @services.each_value do |service|
        # Compile merged pipelines once
        ServiceMethod.values.each do |m|
          app_b = collect_rules(m, RulePhase::Before)
          svc_b = service.collect_rules(m, RulePhase::Before)
          service.set_before_pipeline(m, app_b, svc_b)

          svc_a = service.collect_rules(m, RulePhase::After)
          app_a = collect_rules(m, RulePhase::After)
          service.set_after_pipeline(m, svc_a, app_a)
        end
      end
      @pipelines_compiled = true
    end

    # Central dispatch using merged pipelines (2 Orchestrator calls)
    def dispatch(service : Service, ctx : RuleContext) : RuleContext
      compile_pipelines! unless @pipelines_compiled
      m = ctx.method

      # 1. BEFORE (app + service)
      ctx.phase = RulePhase::Before
      before_rules = service.before_pipeline(m)
      ok, stopped_in_app = Orchestrator.run_bounded(before_rules, ctx, service.before_app_len(m), short_circuit: true)

      unless ok
        ctx.phase = RulePhase::Error
        # run service error only if stop happened in service part
        Orchestrator.run(service.collect_rules(m, RulePhase::Error), ctx) unless stopped_in_app
        Orchestrator.run(collect_rules(m, RulePhase::Error), ctx)
        return ctx
      end

      # 2. SERVICE METHOD
      unless ctx.result_set?
        ctx.phase = RulePhase::After
        result, error = service.call_method(ctx)
        if error
          ctx.error = error
          ctx.phase = RulePhase::Error
          Orchestrator.run(service.collect_rules(m, RulePhase::Error), ctx)
          Orchestrator.run(collect_rules(m, RulePhase::Error), ctx)
          return ctx
        end
        ctx.result = result
      end

      # 3. AFTER (service + app)
      ctx.phase = RulePhase::After
      after_rules = service.after_pipeline(m)
      unless Orchestrator.run(after_rules, ctx)
        ctx.phase = RulePhase::Error
        Orchestrator.run(collect_rules(m, RulePhase::Error), ctx)
      end
      ctx
    end

    def listen(port : Int32 = 3000, *, host : String = "127.0.0.1", trusted_proxies : TrustedProxies = nil)
      compile_pipelines! # freeze once, after all rules are registered

      router = Http::Router.new(self, trusted_proxies)
      server = HTTP::Server.new { |ctx| router.handle(ctx) }
      server.bind_tcp(host, port, reuse_port: false)

      display_host = host.includes?(':') ? "[#{host}]" : host
      puts "Listening on http://#{display_host}:#{port}"

      if host == "0.0.0.0" || host == "::"
        STDERR.puts "Warning: binding to #{host} exposes the server on all interfaces"
      end

      server.listen
    end
  end
end
