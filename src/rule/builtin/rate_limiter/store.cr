module Alumna
  # Persistence for rate-limit counters. MemoryRateLimitStore is the in-process
  # store. A Redis store can implement hit and drop in.
  #
  # hit returns {count, reset_at_utc} or StoreError (store down).
  # count is the value after this hit. reset_at is wall clock for
  # X-RateLimit-Reset. MemoryRateLimitStore never returns StoreError.
  abstract class RateLimitStore
    abstract def hit(key : String) : Tuple(Int32, Time) | StoreError
  end
end
