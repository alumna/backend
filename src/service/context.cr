require "json"
require "http"

module Alumna
  # forward declarations — full bodies live in http/router.cr
  module Http
    struct ParamsView; end

    struct HeadersView; end
  end

  alias ServiceResult = Hash(String, AnyData) | Array(Hash(String, AnyData)) | Nil

  class RuleContext
    getter app : App
    getter service : Service
    getter path : String
    getter method : ServiceMethod
    getter phase : RulePhase
    getter http_method : String
    getter remote_ip : String

    property params : Http::ParamsView
    property provider : String
    property id : String?
    property data : Hash(String, AnyData)
    property result : ServiceResult
    property error : ServiceError?
    property http : HttpOverrides
    property headers : Http::HeadersView
    property store : Hash(String, AnyData)

    protected setter phase

    def initialize(
      @app : App,
      @service : Service,
      @path : String,
      @method : ServiceMethod,
      @phase : RulePhase,
      @params : Http::ParamsView,
      @headers : Http::HeadersView,
      @http_method : String = "GET",
      @remote_ip : String = "",
      @provider : String = "rest",
      @id : String? = nil,
      @data : Hash(String, AnyData) = {} of String => AnyData,
    )
      @result = nil
      @error = nil
      @http = HttpOverrides.new
      @store = {} of String => AnyData
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
