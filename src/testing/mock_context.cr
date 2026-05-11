module Alumna
  module Testing
    # Utility to quickly fabricate a RuleContext for testing purposes.
    # Provides sensible defaults so you only need to override what you are testing.
    def self.build_ctx(
      app : App = App.new,
      service : Service = MemoryAdapter.new,
      path : String = "/test",
      method : ServiceMethod = ServiceMethod::Find,
      phase : RulePhase = RulePhase::Before,
      params : Hash(String, String) = {} of String => String,
      headers : Hash(String, String) = {} of String => String,
      http_method : String = "GET",
      remote_ip : String = "127.0.0.1",
      provider : String = "rest",
      id : String? = nil,
      data : Hash(String, AnyData) = {} of String => AnyData,
    ) : RuleContext
      http_params = HTTP::Params.new
      params.each { |k, v| http_params.add(k, v) }

      http_headers = HTTP::Headers.new
      headers.each { |k, v| http_headers.add(k, v) }

      RuleContext.new(
        app: app,
        service: service,
        path: path,
        method: method,
        phase: phase,
        params: Http::ParamsView.new(http_params),
        headers: Http::HeadersView.new(http_headers),
        http_method: http_method,
        remote_ip: remote_ip,
        provider: provider,
        id: id,
        data: data
      )
    end
  end
end
