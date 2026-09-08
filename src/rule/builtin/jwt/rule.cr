module Alumna
  def self.jwt(
    secret : String | Bytes,
    store_key : String = "jwt",
    header : String = "Authorization",
    scheme : String = "Bearer",
    required : Bool = true,
    skip_providers : Array(String) = Session::DEFAULT_SKIP,
    leeway : Time::Span = Time::Span.zero,
    iss : String? = nil,
    aud : String? = nil,
  ) : Rule
    key = secret.to_slice
    raise ArgumentError.new("jwt secret must not be empty") if key.empty?
    raise ArgumentError.new("jwt header name must not be empty") if header.empty?

    Rule.new do |ctx|
      next nil if ctx.http_method == "OPTIONS"
      next nil if skip_providers.includes?(ctx.provider)

      raw = ctx.headers[header]?
      if raw.nil?
        next required ? ServiceError.unauthorized("Missing token") : nil
      end
      token = bearer_token(raw, scheme)
      if token.nil? || token.empty?
        next ServiceError.unauthorized
      end

      result = JWT.verify(token, key, leeway: leeway, iss: iss, aud: aud)
      if result.is_a?(ServiceError)
        next result
      end
      ctx.store[store_key] = result
      nil
    end
  end

  private def self.bearer_token(value : String, scheme : String) : String?
    if scheme.empty?
      return value.empty? ? nil : value
    end
    n = scheme.bytesize
    return nil if value.bytesize < n + 1
    return nil unless value.byte_at(n) == 0x20
    n.times do |i|
      a = value.byte_at(i)
      b = scheme.byte_at(i)
      a |= 32 if a >= 65 && a <= 90
      b |= 32 if b >= 65 && b <= 90
      return nil unless a == b
    end
    token = value.byte_slice(n + 1, value.bytesize - n - 1)
    token.empty? ? nil : token
  end
end
