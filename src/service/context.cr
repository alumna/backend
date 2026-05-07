require "json"
require "http"

module Alumna
  # forward declarations - full bodies live in http/router.cr
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

    @query : Query?

    def query : Query
      @query ||= Query.new(@params)
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
      @error = nil
      @http = HttpOverrides.new
      @store = {} of String => AnyData
    end

    def result_set? : Bool
      !@result.nil?
    end

    # ---- typed data accessors (zero-cost, inlined) ----
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

  class Query
    getter filters : Hash(String, String)
    getter limit : Int32?
    getter skip : Int32?
    getter sort : Array(Tuple(String, Int32))?
    getter select : Array(String)?

    def initialize(params : Http::ParamsView)
      @filters = {} of String => String
      @limit = nil
      @skip = nil
      @sort = nil
      @select = nil

      params.each do |k, v|
        case k
        when "$limit"
          @limit = v.to_i? if v.matches?(/^\d+$/)
        when "$skip"
          @skip = v.to_i? if v.matches?(/^\d+$/)
        when "$sort"
          # "age:-1,name:1" → [{"age",-1},{"name",1}]
          @sort = v.split(',').compact_map do |part|
            field, dir = part.split(':', 2)
            next if field.empty?
            dir_i = dir.try(&.to_i?) || 1
            {field, dir_i >= 0 ? 1 : -1}
          end
        when "$select"
          @select = v.split(',').map(&.strip).reject(&.empty?)
        else
          @filters[k] = v unless k.starts_with?('$')
        end
      end
    end

    def empty? : Bool
      @filters.empty? && @limit.nil? && @skip.nil? && @sort.nil? && @select.nil?
    end
  end
end
