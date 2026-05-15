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
    @store : Hash(String, AnyData)?
    @query : Query?

    def query : Query
      @query ||= Query.new(@params)
    end

    def store : Hash(String, AnyData)
      @store ||= {} of String => AnyData
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

  class Query
    enum Op
      Eq
      Ne
      Gt
      Gte
      Lt
      Lte
      In
      Nin
    end

    struct Condition
      getter op : Op
      getter value : String | Array(String)

      def initialize(@op : Op, @value : String | Array(String))
      end
    end

    getter filters : Hash(String, Array(Condition))
    getter limit : Int32?
    getter skip : Int32?
    getter sort : Array(Tuple(String, Int32))?
    getter select : Array(String)?

    def initialize(params : Http::ParamsView)
      @filters = Hash(String, Array(Condition)).new { |h, k| h[k] = [] of Condition }
      @limit = nil
      @skip = nil
      @sort = nil
      @select = nil

      params.each do |k, v|
        case k
        when "$limit"
          @limit = parse_positive_int v
        when "$skip"
          @skip = parse_positive_int v
        when "$sort"
          @sort = v.split(',').compact_map do |part|
            field, dir = part.split(':', 2)
            next if field.empty?
            dir_i = dir.try(&.to_i?) || 1
            {field, dir_i >= 0 ? 1 : -1}
          end
        when "$select"
          @select = v.split(',').map(&.strip).reject(&.empty?)
        else
          next if k.starts_with?('$')

          field = k
          op_str = "$eq"

          if k.ends_with?(']') && (bracket_idx = k.index('['))
            field = k[0...bracket_idx]
            op_str = k[bracket_idx + 1...-1]
          end

          op = parse_op(op_str)
          if op.nil?
            field = k
            op = Op::Eq
          end

          if op.in? || op.nin?
            val = v.split(',')
            @filters[field] << Condition.new(op, val)
          else
            @filters[field] << Condition.new(op, v)
          end
        end
      end
    end

    def empty? : Bool
      @filters.empty? && @limit.nil? && @skip.nil? && @sort.nil? && @select.nil?
    end

    private def parse_op(s : String) : Op?
      case s
      when "$eq"  then Op::Eq
      when "$ne"  then Op::Ne
      when "$gt"  then Op::Gt
      when "$gte" then Op::Gte
      when "$lt"  then Op::Lt
      when "$lte" then Op::Lte
      when "$in"  then Op::In
      when "$nin" then Op::Nin
      else             nil
      end
    end

    @[AlwaysInline]
    private def parse_positive_int(str : String) : Int32?
      return nil if str.empty?
      str.each_byte { |b| return nil unless 48 <= b <= 57 }
      str.to_i?
    end
  end
end
