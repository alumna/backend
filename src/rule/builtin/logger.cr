module Alumna
  # One process-wide reference — subtraction stays monotonic
  START = Time.instant

  def self.logger(io : IO = STDOUT) : Rule
    Rule.new do |ctx|
      if ctx.phase.before?
        # store as Int64, not Float64
        ctx.store["t0"] = (Time.instant - START).total_nanoseconds.to_i64
      else
        t0 = ctx.store["t0"]?.as?(Int64)
        now = (Time.instant - START).total_nanoseconds.to_i64
        ms = t0 ? ((now - t0) / 1_000_000.0).round(1) : 0.0

        status = ctx.http.status || ctx.error.try(&.status) || 200
        path = ctx.id ? "#{ctx.path}/#{ctx.id}" : ctx.path

        io.puts %(#{ctx.remote_ip} "#{ctx.http_method} #{path}" #{status} #{ms}ms)
      end
      RuleResult.continue
    end
  end
end
