require "http/server"

module Alumna
  class App
    include Ruleable

    alias TrustedProxies = Bool | Array(String) | Nil

    getter serializer : Http::Serializer
    getter services : Hash(String, Service)

    property max_body_size : Int64 = 1_048_576

    @pipeline_mutex : Sync::Mutex
    @pipelines_compiled : Atomic(Bool)

    def initialize(@serializer : Http::Serializer = Http::JsonSerializer.new)
      @services = {} of String => Service
      @pipelines_compiled = Atomic(Bool).new(false)
      @pipeline_mutex = Sync::Mutex.new
    end

    def use(path : String, service : Service) : self
      normalized = normalize_path(path)
      raise ArgumentError.new("service already mounted at #{normalized}") if @services.has_key?(normalized)
      service.path = normalized
      @services[normalized] = service
      self
    end

    private def normalize_path(path) : String
      raise ArgumentError.new("path must start with '/'") unless path.starts_with?('/')
      path == "/" ? path : path.chomp('/')
    end

    private def compile_pipelines!
      # Outer fast path: :acquire pairs with the :release write below,
      # ensuring all pipeline writes are visible once we see true.
      return if @pipelines_compiled.get(:acquire)

      @pipeline_mutex.synchronize do
        # Inner check: the mutex lock already carries :acquire semantics,
        # so :relaxed is sufficient here.
        return if @pipelines_compiled.get(:relaxed)

        @services.each_value do |service|
          # Compile merged pipelines once
          ServiceMethod.values.each do |m|
            app_b = collect_rules(m, RulePhase::Before)
            svc_b = service.collect_rules(m, RulePhase::Before)
            service.set_before_pipeline(m, app_b, svc_b)

            svc_a = service.collect_rules(m, RulePhase::After)
            app_a = collect_rules(m, RulePhase::After)
            service.set_after_pipeline(m, svc_a, app_a)

            svc_e = service.collect_rules(m, RulePhase::Error)
            app_e = collect_rules(m, RulePhase::Error)
            service.set_error_pipeline(m, svc_e, app_e)
          end
        end
        # :release ensures all pipeline writes above are visible to any
        # thread that subsequently reads with :acquire.
        @pipelines_compiled.set(true, :release)
      end
    end

    # Central dispatch using merged pipelines
    def dispatch(service : Service, ctx : RuleContext) : RuleContext
      compile_pipelines! unless @pipelines_compiled.get(:acquire)
      m = ctx.method

      # 1. BEFORE (app + service)
      ctx.phase = RulePhase::Before
      before_rules = service.before_pipeline(m)
      ok, stopped_in_app = Orchestrator.run_bounded(before_rules, ctx, service.before_app_len(m), short_circuit: true)

      unless ok
        ctx.phase = RulePhase::Error
        # run service error only if stop happened in service part
        start_idx = stopped_in_app ? service.error_svc_len(m) : 0
        Orchestrator.run(service.error_pipeline(m), ctx, start: start_idx)
        return ctx
      end

      # 2. SERVICE METHOD
      unless ctx.result_set?
        ctx.phase = RulePhase::After
        result, error = service.call_method(ctx)
        if error
          ctx.error = error
          ctx.phase = RulePhase::Error
          Orchestrator.run(service.error_pipeline(m), ctx)
          return ctx
        end
        ctx.result = result
      end

      # 3. AFTER (service + app)
      ctx.phase = RulePhase::After
      after_rules = service.after_pipeline(m)
      unless Orchestrator.run(after_rules, ctx)
        ctx.phase = RulePhase::Error
        Orchestrator.run(service.error_pipeline(m), ctx)
      end
      ctx
    end

    def listen(
      port : Int32 = 3000,
      *,
      host : String = "127.0.0.1",
      trusted_proxies : TrustedProxies = nil,
      workers : Int32? = nil,
    )
      compile_pipelines! # freeze once, after all rules are registered

      workers_msg = ""
      {% if flag?(:execution_context) %}
        actual_workers = workers || Fiber::ExecutionContext.default_workers_count
        Fiber::ExecutionContext.default.resize(actual_workers.clamp(1..))
        workers_msg = " (#{actual_workers} workers)"
      {% else %}
        if workers && workers > 1
          STDERR.puts "Warning: 'workers' argument ignored. To enable multithreading, compile with: -Dpreview_mt -Dexecution_context"
        end
        workers_msg = " (single-threaded)"
      {% end %}

      router = Http::Router.new(self, trusted_proxies)
      server = HTTP::Server.new { |ctx| router.handle(ctx) }

      # reuse_port is no longer needed since Crystal threads share the same socket
      server.bind_tcp(host, port)

      display_host = host.includes?(':') ? "[#{host}]" : host
      puts "Listening on http://#{display_host}:#{port}#{workers_msg}"

      if host == "0.0.0.0" || host == "::"
        STDERR.puts "Warning: binding to #{host} exposes the server on all interfaces"
      end

      server.listen
    end
  end
end
