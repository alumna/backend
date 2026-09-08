module Alumna
  # In-process session map. Use one instance per process (single backend).
  # Swap for a Redis SessionStore to share sessions across processes.
  #
  # Expiry uses Time.instant (monotonic). Cookie Max-Age uses wall clock.
  # No background fiber. Expired rows are dropped on get and by an amortized
  # prune every `cleanup_every` writes/reads, same as RateLimitStore.
  class MemorySessionStore < SessionStore
    record Entry, data : Hash(String, AnyData), deadline : Time::Instant

    def initialize(ttl : Time::Span = 24.hours, cleanup_every : Int32 = 1024)
      super(ttl)
      raise ArgumentError.new("cleanup_every must be >= 1") if cleanup_every < 1
      @store = {} of String => Entry
      @mutex = Sync::Mutex.new
      @ops = 0
      @cleanup_every = cleanup_every
    end

    def get(id : String) : Hash(String, AnyData)?
      now = Time.instant
      @mutex.synchronize do
        prune_if_due(now)
        entry = @store[id]?
        return nil unless entry
        if now >= entry.deadline
          @store.delete(id)
          return nil
        end
        entry.data.dup
      end
    end

    def set(id : String, data : Hash(String, AnyData), ttl : Time::Span = default_ttl) : Nil
      raise ArgumentError.new("session ttl must be > 0") if ttl <= Time::Span.zero
      now = Time.instant
      @mutex.synchronize do
        @store[id] = Entry.new(data.dup, now + ttl)
        prune_if_due(now)
      end
    end

    def delete(id : String) : Nil
      @mutex.synchronize { @store.delete(id) }
    end

    # Spec helper. Not used by the Rule.
    def size : Int32
      @mutex.synchronize { @store.size }
    end

    # Spec helper. Not used by the Rule.
    def prune_expired : Nil
      now = Time.instant
      @mutex.synchronize { @store.reject! { |_, e| now >= e.deadline } }
    end

    private def prune_if_due(now : Time::Instant) : Nil
      @ops += 1
      return if @ops < @cleanup_every
      @ops = 0
      @store.reject! { |_, e| now >= e.deadline }
    end
  end
end
