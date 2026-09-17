require "mutex"

module Alumna
  # In-process byte cache. Use one instance per process (single backend).
  # Swap for a Redis Cache to share entries across processes.
  #
  # Expiry uses Time.instant (monotonic). No background fiber. Expired rows
  # are dropped on get and by an amortized prune every `cleanup_every`
  # writes/reads, same as MemorySessionStore.
  class MemoryCache < Cache
    record Entry, value : Bytes, deadline : Time::Instant?

    def initialize(cleanup_every : Int32 = 1024)
      raise ArgumentError.new("cleanup_every must be >= 1") if cleanup_every < 1
      @store = {} of String => Entry
      @mutex = Sync::Mutex.new
      @ops = 0
      @cleanup_every = cleanup_every
    end

    def get(key : String) : Bytes?
      now = Time.instant
      @mutex.synchronize do
        prune_if_due(now)
        entry = @store[key]?
        return nil unless entry
        if expired?(entry, now)
          @store.delete(key)
          return nil
        end
        entry.value.dup
      end
    end

    def set(key : String, value : Bytes, ttl : Time::Span? = nil) : Nil
      deadline = deadline_for(ttl)
      now = Time.instant
      @mutex.synchronize do
        @store[key] = Entry.new(value.dup, deadline)
        prune_if_due(now)
      end
    end

    # True if the key was missing or expired and this call stored the value.
    def set_nx(key : String, value : Bytes, ttl : Time::Span? = nil) : Bool
      deadline = deadline_for(ttl)
      now = Time.instant
      @mutex.synchronize do
        prune_if_due(now)
        if entry = @store[key]?
          return false unless expired?(entry, now)
        end
        @store[key] = Entry.new(value.dup, deadline)
        true
      end
    end

    def delete(key : String) : Nil
      @mutex.synchronize { @store.delete(key) }
    end

    # Atomic +1. Missing, expired, or non-integer values start at 1.
    # The stored counter has no TTL.
    def incr(key : String) : Int64
      now = Time.instant
      @mutex.synchronize do
        prune_if_due(now)
        n = 0_i64
        if entry = @store[key]?
          unless expired?(entry, now)
            if parsed = String.new(entry.value).to_i64?
              n = parsed
            end
          end
        end
        n += 1
        @store[key] = Entry.new(n.to_s.to_slice.dup, nil)
        n
      end
    end

    # Spec helper. Not used by the cache rule.
    def size : Int32
      @mutex.synchronize { @store.size }
    end

    # Spec helper. Not used by the cache rule.
    def prune_expired : Nil
      now = Time.instant
      @mutex.synchronize { @store.reject! { |_, e| expired?(e, now) } }
    end

    private def deadline_for(ttl : Time::Span?) : Time::Instant?
      if ttl && ttl <= Time::Span.zero
        raise ArgumentError.new("cache ttl must be > 0")
      end
      ttl ? Time.instant + ttl : nil
    end

    private def expired?(entry : Entry, now : Time::Instant) : Bool
      deadline = entry.deadline
      return false unless deadline
      now >= deadline
    end

    private def prune_if_due(now : Time::Instant) : Nil
      @ops += 1
      return if @ops < @cleanup_every
      @ops = 0
      @store.reject! { |_, e| expired?(e, now) }
    end
  end
end
