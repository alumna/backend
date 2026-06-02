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
    )
    end

    def result=(value : ServiceResult)
      @result = value
      @result_set = true
    end

    # Dispatches a request to another internal service, bypassing the HTTP network stack
    # but still running through the target service's schema validations and rules.
    def call(
      path : String,
      method : ServiceMethod | Symbol,
      data : Hash(String, AnyData) = {} of String => AnyData,
      id : String? = nil,
    ) : ServiceResult
      target_service = app.services[path]?
      raise ArgumentError.new("Internal service not found at path: #{path}") unless target_service

      parsed_method = method.is_a?(ServiceMethod) ? method : ServiceMethod.parse(method.to_s.capitalize)

      internal_ctx = RuleContext.new(
        app: app,
        service: target_service,
        path: path,
        method: parsed_method,
        phase: RulePhase::Before,
        http_method: "INTERNAL",
        remote_ip: remote_ip,
        provider: "internal",
        params: params,   # Inherit params view
        headers: headers, # Inherit headers view
        id: id,
        data: data
      )

      # Shallow copy the store so authenticated users/transaction IDs flow down,
      # but downstream mutations don't pollute the parent request state.
      if s = @store
        s.each { |k, v| internal_ctx.store[k] = v }
      end

      app.dispatch(target_service, internal_ctx)

      # If the sub-service threw an error (e.g., validation failed), re-raise it
      # so the calling rule/service can rescue it, or let it halt the current pipeline.
      if err = internal_ctx.error
        raise Exception.new("Internal call to #{path} failed: #{err.status} #{err.message}")
      end

      internal_ctx.result
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
