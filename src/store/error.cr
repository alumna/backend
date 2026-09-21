module Alumna
  # Failure from Cache, SessionStore, or RateLimitStore.
  # Not a cache miss (Cache#get nil) and not a missing session (SessionStore#get nil).
  # Memory implementations never construct this type.
  # Rules map it to ServiceError.internal. Do not put ServiceError on the port.
  struct StoreError
    getter message : String

    def initialize(@message : String)
    end

    def to_s(io : IO) : Nil
      io << @message
    end
  end
end
