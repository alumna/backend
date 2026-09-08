require "random/secure"

module Alumna
  # Persistence for session records. MemorySessionStore is the in-process
  # adapter. A Redis adapter can implement the same three methods and drop in.
  #
  # get/set copy the data hash (shallow). In-place mutation of a returned hash
  # does not change the store. Call set to persist. This matches a remote store.
  #
  # TTL is absolute from the last set. The store does not slide the deadline
  # on get. Pass a different ttl to set or Session.start when needed.
  abstract class SessionStore
    getter default_ttl : Time::Span

    def initialize(@default_ttl : Time::Span)
      raise ArgumentError.new("session ttl must be > 0") if @default_ttl <= Time::Span.zero
    end

    def new_id : String
      Random::Secure.urlsafe_base64(32, padding: false)
    end

    abstract def get(id : String) : Hash(String, AnyData)?
    abstract def set(id : String, data : Hash(String, AnyData), ttl : Time::Span) : Nil
    abstract def delete(id : String) : Nil
  end
end
