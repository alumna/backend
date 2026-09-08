require "base64"
require "openssl/hmac"
require "crypto/subtle"

module Alumna
  module JWT
    HEADER_B64 = Base64.urlsafe_encode(%({"alg":"HS256","typ":"JWT"}), padding: false)

    def self.encode(payload : Hash(String, AnyData), secret : String | Bytes) : String
      key = secret.to_slice
      raise ArgumentError.new("jwt secret must not be empty") if key.empty?
      body = Base64.urlsafe_encode(JsonHelper.to_string(payload), padding: false)
      signing = String.build { |io| io << HEADER_B64 << '.' << body }
      sig = sign(key, signing)
      String.build { |io|
        io << signing << '.'
        io << Base64.urlsafe_encode(sig, padding: false)
      }
    end

    # Returns claims or a 401. Does not raise for a bad token.
    def self.verify(
      token : String,
      secret : Bytes,
      leeway : Time::Span = Time::Span.zero,
      iss : String? = nil,
      aud : String? = nil,
    ) : Hash(String, AnyData) | ServiceError
      d1 = token.index('.')
      return unauthorized unless d1
      d2 = token.index('.', d1 + 1)
      return unauthorized unless d2
      return unauthorized if token.index('.', d2 + 1)
      return unauthorized if d1 == 0 || d2 == d1 + 1 || d2 + 1 == token.bytesize

      header_b64 = token[0, d1]
      payload_b64 = token[d1 + 1, d2 - d1 - 1]
      sig_b64 = token[d2 + 1, token.bytesize - d2 - 1]
      signing = token[0, d2]

      header = decode_object(header_b64)
      return unauthorized unless header
      alg = header["alg"]?.as?(String)
      return unauthorized unless alg == "HS256"

      expected = sign(secret, signing)
      got = decode_bytes(sig_b64)
      return unauthorized unless got
      return unauthorized unless Crypto::Subtle.constant_time_compare(expected, got)

      claims = decode_object(payload_b64)
      return unauthorized unless claims
      check_time_claims(claims, leeway) || check_party_claims(claims, iss, aud) || claims
    end

    def self.sign(secret : Bytes, data : String) : Bytes
      OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, secret, data)
    end

    private def self.decode_bytes(part : String) : Bytes?
      Base64.decode(part)
    rescue Base64::Error
      nil
    end

    private def self.decode_object(part : String) : Hash(String, AnyData)?
      bytes = decode_bytes(part)
      return nil unless bytes
      json = String.new(bytes)
      val = JsonHelper.from_string(json)
      val.as?(Hash(String, AnyData))
    rescue JSON::ParseException
      nil
    end

    private def self.check_time_claims(claims : Hash(String, AnyData), leeway : Time::Span) : ServiceError?
      now = Time.utc.to_unix
      skew = leeway.total_seconds.to_i64
      if exp = claims["exp"]?.as?(Int64)
        return ServiceError.unauthorized("Token expired") if now > exp + skew
      end
      if nbf = claims["nbf"]?.as?(Int64)
        return unauthorized if now + skew < nbf
      end
      if iat = claims["iat"]?.as?(Int64)
        return unauthorized if iat > now + skew
      end
      nil
    end

    private def self.check_party_claims(claims : Hash(String, AnyData), iss : String?, aud : String?) : ServiceError?
      if iss
        return unauthorized unless claims["iss"]?.as?(String) == iss
      end
      if aud
        return unauthorized unless aud_match?(claims["aud"]?, aud)
      end
      nil
    end

    private def self.aud_match?(value : AnyData?, aud : String) : Bool
      case value
      when String then value == aud
      when Array
        value.any? { |item| item.as?(String) == aud }
      else
        false
      end
    end

    private def self.unauthorized
      ServiceError.unauthorized
    end
  end
end
