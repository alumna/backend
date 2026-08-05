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
    getter provider : String
    getter id : String?

    property params : Http::ParamsView
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
      @store : Hash(String, StoreType)? = nil,
    )
    end

    def result=(value : ServiceResult)
      @result = value
      @result_set = true
    end

    # Dispatches a request to another internal service, bypassing the HTTP network stack.
    # Dynamically resolves paths (e.g., "/users/123") and isolates query params by default.
    def call(
      path : String,
      method : ServiceMethod | Symbol,
      data : Hash(String, AnyData) = {} of String => AnyData,
      params : Hash(String, String)? = nil,
      id : String? = nil,
    ) : {ServiceResult, ServiceError?}
      target_service = app.services[path]?
      resolved_path = path
      resolved_id = id

      # If strict path not found, attempt to resolve dynamic path (e.g., /users/123)
      if target_service.nil?
        sep = path.index('/', 1)
        if sep && !path.index('/', sep + 1)
          base = path[0...sep]
          if svc = app.services[base]?
            target_service = svc
            resolved_path = base
            resolved_id = path[sep + 1..]
          end
        end
      end

      return {nil, ServiceError.internal("Internal service not found at path: #{path}")} unless target_service

      # Zero-allocation symbol parsing for the hot path
      parsed_method = if method.is_a?(ServiceMethod)
                        method
                      else
                        case method
                        when :find    then ServiceMethod::Find
                        when :get     then ServiceMethod::Get
                        when :create  then ServiceMethod::Create
                        when :update  then ServiceMethod::Update
                        when :patch   then ServiceMethod::Patch
                        when :remove  then ServiceMethod::Remove
                        when :options then ServiceMethod::Options
                        else               ServiceMethod.parse(method.to_s.capitalize)
                        end
                      end

      # Isolate params by default to prevent accidental leaky queries from the parent request.
      http_params = HTTP::Params.new
      params.try &.each { |k, v| http_params.add(k, v) }
      internal_params = Http::ParamsView.new(http_params)

      internal_ctx = RuleContext.new(
        app: app,
        service: target_service,
        path: resolved_path,
        method: parsed_method,
        phase: RulePhase::Before,
        http_method: "INTERNAL",
        remote_ip: remote_ip,
        provider: "internal",
        params: internal_params,
        headers: headers, # Inherit headers view (safe for cross-cutting tracing/auth)
        id: resolved_id,
        data: data,
        store: @store.try(&.dup) # Fast shallow copy via Hash#dup
      )

      app.dispatch(target_service, internal_ctx)

      {internal_ctx.result, internal_ctx.error}
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
