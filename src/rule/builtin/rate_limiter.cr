require "./rate_limiter/store"
require "./rate_limiter/memory_store"

module Alumna
  # Fixed-window rate limiter. Default store is MemoryRateLimitStore.
  # Pass store: to inject another RateLimitStore (for example Redis).
  # window_seconds sets the memory store window when store: is omitted.
  # Store-down is ServiceError.internal (fail closed). Not 429.
  def self.rate_limit(
    limit : Int32 = 100,
    window_seconds : Int32 = 60,
    key : Proc(RuleContext, String) = ->(ctx : RuleContext) { ctx.remote_ip },
    store : RateLimitStore? = nil,
  ) : Rule
    resolved = store || MemoryRateLimitStore.new(window_seconds.seconds)

    Rule.new do |ctx|
      next nil if ctx.http_method == "OPTIONS"

      hit = resolved.hit(key.call(ctx))
      if hit.is_a?(StoreError)
        next ServiceError.internal(hit.message)
      end
      count, reset_at = hit

      ctx.http.headers["X-RateLimit-Limit"] = limit.to_s
      # LCOV_EXCL_START - kcov misses chained clamp, covered by spec
      ctx.http.headers["X-RateLimit-Remaining"] = (limit - count).clamp(0, limit).to_s
      # LCOV_EXCL_STOP
      ctx.http.headers["X-RateLimit-Reset"] = reset_at.to_unix.to_s

      if count > limit
        ServiceError.new("Too Many Requests", 429)
      else
        nil
      end
    end
  end
end
