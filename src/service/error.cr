module Alumna
  struct ServiceError
    getter status : Int32
    getter message : String
    @details : Hash(String, AnyData)?

    def initialize(@message : String, @status : Int32 = 400, details : Hash(String, AnyData)? = nil)
      @details = (details && !details.empty?) ? details : nil
    end

    # Returns the details hash, allocating a temporary empty one if none exists.
    # Because ServiceError is a struct (value type), we intentionally avoid lazy-mutating
    # (@details ||=) to prevent unintended copy semantics and state divergence.
    def details : Hash(String, AnyData)
      @details || ({} of String => AnyData)
    end

    def details? : Hash(String, AnyData)?
      @details
    end

    def self.bad_request(message : String, details : Hash(String, AnyData)? = nil)
      new(message, 400, details)
    end

    # Auto-casting helper for fluid DX.
    # Note: Crystal's overload resolution cleanly prefers the `details = nil`
    # method signature when called without any kwargs.
    def self.bad_request(message : String, **kwargs)
      new(message, 400, kwargs_to_details(kwargs))
    end

    def self.unauthorized(message : String = "Unauthorized")
      new(message, 401)
    end

    def self.forbidden(message : String = "Forbidden")
      new(message, 403)
    end

    def self.not_found(message : String = "Not found")
      new(message, 404)
    end

    def self.unprocessable(message : String, details : Hash(String, AnyData)? = nil)
      new(message, 422, details)
    end

    # Auto-casting helper for fluid DX.
    # Note: Crystal's overload resolution cleanly prefers the `details = nil`
    # method signature when called without any kwargs.
    def self.unprocessable(message : String, **kwargs)
      new(message, 422, kwargs_to_details(kwargs))
    end

    def self.internal(message : String = "Internal server error")
      new(message, 500)
    end

    # Pre-sizes the hash to avoid the default growth/rehash cycle.
    # Since kwargs.size is known at compile-time (it's a NamedTuple),
    # this provides a free, zero-overhead performance win.
    private def self.kwargs_to_details(kwargs) : Hash(String, AnyData)
      h = Hash(String, AnyData).new(initial_capacity: kwargs.size)
      kwargs.each { |k, v| h[k.to_s] = Alumna.to_any(v) }
      h
    end
  end
end
