require "json"

module Alumna
  alias ServiceResult = Hash(String, AnyData) | Array(Hash(String, AnyData)) | Nil

  class RuleContext
    # --- Read-only ---
    getter app : App
    getter service : Service
    getter path : String
    getter method : ServiceMethod
    getter phase : RulePhase

    # --- Writable ---
    property params : Hash(String, String)
    property provider : String
    property id : String?
    property data : Hash(String, AnyData)
    property result : ServiceResult
    property error : ServiceError?
    property http : HttpOverrides
    property headers : Hash(String, String)

    protected setter phase

    def initialize(
      @app : App,
      @service : Service,
      @path : String,
      @method : ServiceMethod,
      @phase : RulePhase,
      @params : Hash(String, String) = {} of String => String,
      @provider : String = "rest",
      @id : String? = nil,
      @data : Hash(String, AnyData) = {} of String => AnyData,
      @headers : Hash(String, String) = {} of String => String,
    )
      @result = nil
      @error = nil
      @http = HttpOverrides.new
    end

    def result_set? : Bool
      !@result.nil?
    end
  end

  struct HttpOverrides
    property status : Int32?
    property headers : Hash(String, String)
    property location : String?

    def initialize
      @status = nil
      @headers = {} of String => String
      @location = nil
    end
  end
end
