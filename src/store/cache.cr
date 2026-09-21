module Alumna
  # Byte cache with optional TTL. MemoryCache is the in-process store.
  # A Redis cache can implement get, set, set_nx, delete, and incr and drop in.
  #
  # Values are Bytes. Alumna.cache encodes AnyData as JSON. This port
  # does not encode.
  #
  # get/set copy the byte slice. In-place mutation of a returned slice
  # does not change the store. Call set to persist. This matches a remote store.
  #
  # ttl nil means no expiry. A positive ttl is absolute from that set.
  # The store does not slide the deadline on get.
  #
  # set_nx sets only when the key is missing or expired. True if it wrote.
  # The get rule uses set on write-through and set_nx on miss fill.
  #
  # incr is atomic. Missing or non-integer values become 1. The counter
  # has no TTL. The find rule uses it as a collection generation.
  #
  # get is Bytes (hit), nil (miss), or StoreError (store down). Nil is never
  # a failure. MemoryCache never returns StoreError.
  abstract class Cache
    abstract def get(key : String) : Bytes? | StoreError
    abstract def set(key : String, value : Bytes, ttl : Time::Span? = nil) : Nil | StoreError
    abstract def set_nx(key : String, value : Bytes, ttl : Time::Span? = nil) : Bool | StoreError
    abstract def delete(key : String) : Nil | StoreError
    abstract def incr(key : String) : Int64 | StoreError
  end
end

require "./cache/memory"
