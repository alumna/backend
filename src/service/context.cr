require "json"
require "http"

module Alumna
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

    @result_set : Bool = false
    @store : Hash(String, StoreType)?
    @query : Query?

    def query : Query
      @query ||= Query.new(@params)
    end

    def store : Hash(String, StoreType)
      @store ||= {} of String => StoreType
    end

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
      @result_set = false
      @error = nil
      @http = HttpOverrides.new
    end

    def result=(value : ServiceResult)
      @result = value
      @result_set = true
    end

    def result_set? : Bool
      @result_set
    end

    def data_str?(key) : String?
      data[key]?.as?(String)
    end

    def data_int?(key) : Int64?
      data[key]?.as?(Int64)
    end

    def data_float?(key) : Float64?
      data[key]?.as?(Float64)
    end

    def data_bool?(key) : Bool?
      data[key]?.as?(Bool)
    end

    def data_time?(key) : Time?
      data[key]?.as?(Time)
    end

    def data_bytes?(key) : Bytes?
      data[key]?.as?(Bytes)
    end
  end

  struct HttpOverrides
    property status : Int32?
    property location : String?
    @headers : Hash(String, String)?

    def initialize
      @status = nil
      @location = nil
    end

    def headers : Hash(String, String)
      @headers ||= {} of String => String
    end

    def headers? : Hash(String, String)?
      @headers
    end
  end
end
