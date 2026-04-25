module Alumna
  def self.cors(
    origins : Array(String) = ["*"],
    methods : Array(String) = %w(GET POST PUT PATCH DELETE OPTIONS),
    headers : Array(String) = %w(Content-Type Authorization Accept),
    credentials : Bool = false,
    max_age : Int32 = 86400,
  ) : Rule
    allow_methods = methods.join(", ")
    allow_headers = headers.join(", ")
    wildcard = origins.includes?("*")

    Rule.new do |ctx|
      origin = ctx.headers["origin"]?

      allowed = if wildcard
                  "*"
                elsif origin && origins.includes?(origin)
                  origin
                end

      if allowed
        ctx.http.headers["Access-Control-Allow-Origin"] = allowed
        ctx.http.headers["Vary"] = "Origin"
        ctx.http.headers["Access-Control-Allow-Methods"] = allow_methods
        ctx.http.headers["Access-Control-Allow-Headers"] = allow_headers
        ctx.http.headers["Access-Control-Max-Age"] = max_age.to_s
        ctx.http.headers["Access-Control-Allow-Credentials"] = "true" if credentials
      end

      if ctx.http_method == "OPTIONS"
        ctx.http.status = 204
        ctx.result = {} of String => AnyData # short-circuit, service never runs
      end

      RuleResult.continue
    end
  end
end
