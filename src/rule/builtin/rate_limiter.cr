require "mutex"

module Alumna
  def self.rate_limit(
    limit : Int32 = 100,
    window_seconds : Int32 = 60,
    key : Proc(RuleContext, String) = ->(ctx : RuleContext) { ctx.remote_ip },
  ) : Rule
    store = Hash(String, Tuple(Int32, Time)).new
    mutex = Mutex.new

    Rule.new do |ctx|
      next RuleResult.continue if ctx.http_method == "OPTIONS"

      now = Time.utc
      k = key.call(ctx)

      count, reset_at = mutex.synchronize do
        c, r = store[k]? || {0, now + window_seconds.seconds}
        if now > r
          c = 0
          r = now + window_seconds.seconds
        end
        # LCOV_EXCL_START
        c += 1
        # LCOV_EXCL_STOP
        store[k] = {c, r}
        {c, r}
      end

      ctx.http.headers["X-RateLimit-Limit"] = limit.to_s
      # LCOV_EXCL_START
      ctx.http.headers["X-RateLimit-Remaining"] = (limit - count).clamp(0, limit).to_s
      # LCOV_EXCL_STOP
      ctx.http.headers["X-RateLimit-Reset"] = reset_at.to_unix.to_s

      if count > limit
        RuleResult.stop(ServiceError.new("Too Many Requests", 429))
      else
        RuleResult.continue
      end
    end
  end
end
