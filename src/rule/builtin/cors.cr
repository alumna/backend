require "set"

module Alumna
  def self.cors(
    origins : Array(String) = ["*"],
    methods : Array(String) = %w(GET POST PUT PATCH DELETE OPTIONS),
    headers : Array(String) = %w(Content-Type Authorization Accept),
    credentials : Bool = false,
    max_age : Int32 = 86400,
  ) : Rule
    # normalize once – strip whitespace, downcase, drop a trailing slash
    normalized = origins.map { |o| o.strip.downcase.chomp('/') }

    if credentials && normalized.includes?("*")
      raise ArgumentError.new(
        "Alumna.cors: wildcard '*' cannot be used with credentials: true. " +
        "Specify explicit origins."
      )
    end

    allow_methods = methods.join(", ")
    allow_headers = headers.join(", ")
    wildcard = normalized.includes?("*")
    origins_set = wildcard ? nil : normalized.to_set
    max_age_s = max_age.to_s # cached – no allocation per request

    Rule.new do |ctx|
      origin = ctx.headers["origin"]?
      next nil unless origin

      # same normalization for the incoming value – O(1) string ops
      origin_norm = origin.strip.downcase.chomp('/')

      allowed_origin = if wildcard
                         "*"
                       elsif origins_set.try(&.includes?(origin_norm))
                         origin # echo the client's exact value, spec-compliant
                       end

      next nil unless allowed_origin

      h = ctx.http.headers
      h["Access-Control-Allow-Origin"] = allowed_origin
      h["Access-Control-Allow-Credentials"] = "true" if credentials
      h["Vary"] = "Origin" unless wildcard

      if ctx.http_method == "OPTIONS" && ctx.headers["access-control-request-method"]?
        h["Access-Control-Allow-Methods"] = allow_methods
        h["Access-Control-Allow-Headers"] = allow_headers
        h["Access-Control-Max-Age"] = max_age_s

        ctx.http.status = 204
        ctx.result = {} of String => AnyData
      end

      nil
    end
  end
end
