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
    property result : ServiceResult = nil
    property error : ServiceError? = nil
    property http : HttpOverrides = HttpOverrides.new
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
    end

    def result=(value : ServiceResult)
      @result = value
      @result_set = true
    end

    @[AlwaysInline]
    def result_set? : Bool
      @result_set
    end

    # Typed accessors for ctx.data — generated at compile time, zero runtime cost.
    {% for type, suffix in {String => "str", Int64 => "int", Float64 => "float",
                            Bool => "bool", Time => "time", Bytes => "bytes"} %}
      def data_{{suffix.id}}?(key) : {{type}}?
        data[key]?.as?({{type}})
      end
    {% end %}
  end

  struct HttpOverrides
    property status : Int32?
    property location : String?
    @headers : Hash(String, String)?

    def headers : Hash(String, String)
      @headers ||= {} of String => String
    end

    def headers? : Hash(String, String)?
      @headers
    end
  end
end
