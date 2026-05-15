module Alumna
  struct ServiceError
    getter status : Int32
    getter details : Hash(String, AnyData)
    getter message : String

    def initialize(@message : String, @status : Int32 = 400, details : Hash(String, AnyData)? = nil)
      @details = details || {} of String => AnyData
    end

    def self.bad_request(message : String, details = {} of String => AnyData)
      new(message, 400, details)
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

    def self.unprocessable(message : String, details = {} of String => AnyData)
      new(message, 422, details)
    end

    def self.internal(message : String = "Internal server error")
      new(message, 500)
    end
  end
end
