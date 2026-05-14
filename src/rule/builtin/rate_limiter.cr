require "mutex"

# Alumna rate limiter – bounded, monotonic, zero-background implementation
#
# Previous versions kept a Hash(String, Tuple) that was never pruned. Under
# sustained traffic with many unique keys (e.g. a DDoS), the store grew
# indefinitely because expired windows were reset but never deleted.
#
# This version fixes that with three deliberate choices, aligned with Alumna's
# philosophy of simplicity, explicitness, and performance:
#
# 1. Bounded memory
#    - Each entry stores both a wall-clock `reset_at` (for HTTP headers) and a
#      monotonic `deadline` (Time::Instant).
#    - Once `deadline` passes, the entry is useless. It is removed by an
#      amortized sweep that runs every 1,024 hits inside the same Sync::Mutex.
#    - No background fiber, no timers, no hidden state. Memory usage is
#      proportional to keys seen in the last window, not total history.
#
# 2. Monotonic expiry
#    - All decisions use `Time.instant` (monotonic clock), making the limiter
#      immune to NTP adjustments, DST, or manual clock changes.
#    - `Time.utc` is used only to compute `X-RateLimit-Reset` for clients.
#
# 3. Testability and future stores
#    - Logic lives in private `RateLimitStore`, not in the Rule closure.
#    - `size` and `prune_expired` are exposed solely for specs, enabling
#      deterministic tests without sleeps.
#    - The same interface can later back a `RateLimitRedisStore` without
#      touching the Rule API.
#
# Hot path remains O(1): one Hash lookup under a Sync::Mutex. Cleanup is O(N) but
# amortized and infrequent, keeping throughput comparable to Go/Rust
# implementations while staying fully explicit.

module Alumna
  # Private, testable store. Keeps memory bounded to keys active in the last window.
  private class RateLimitStore
    # reset_at is for HTTP headers (wall clock)
    # deadline is for internal expiry (monotonic clock)
    record Entry, count : Int32, reset_at : Time, deadline : Time::Instant

    def initialize(@window : Time::Span, @cleanup_every : Int32 = 1024)
      @store = Hash(String, Entry).new
      @mutex = Sync::Mutex.new
      @ops = 0
    end

    # Returns {current_count, reset_at_utc}
    def hit(key : String) : Tuple(Int32, Time)
      now_mono = Time.instant
      now_utc = Time.utc

      @mutex.synchronize do
        entry = @store[key]?

        # New window if missing or deadline passed (monotonic, not wall clock)
        if entry.nil? || now_mono >= entry.deadline
          reset_at = now_utc + @window
          deadline = now_mono + @window # Time::Instant + Time::Span => Time::Instant
          entry = Entry.new(0, reset_at, deadline)
        end

        entry = Entry.new(entry.count + 1, entry.reset_at, entry.deadline)
        @store[key] = entry

        # Amortized cleanup — same lock, no background fiber
        @ops += 1
        if @ops >= @cleanup_every
          @ops = 0
          @store.reject! { |_, e| now_mono >= e.deadline }
        end

        {entry.count, entry.reset_at}
      end
    end

    # Exposed for specs, not used by the Rule
    def size : Int32
      @mutex.synchronize { @store.size }
    end

    # Exposed an instant-based cleanup for future specs, not used by the Rule
    def prune_expired : Nil
      now = Time.instant
      @mutex.synchronize { @store.reject! { |_, e| now >= e.deadline } }
    end
  end

  def self.rate_limit(
    limit : Int32 = 100,
    window_seconds : Int32 = 60,
    key : Proc(RuleContext, String) = ->(ctx : RuleContext) { ctx.remote_ip },
  ) : Rule
    store = RateLimitStore.new(window_seconds.seconds)

    Rule.new do |ctx|
      next nil if ctx.http_method == "OPTIONS"

      count, reset_at = store.hit(key.call(ctx))

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
