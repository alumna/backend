require "../../../spec_helper"
require "base64"

private SECRET = "s3cret-key-for-tests"

private def token_with_header(header_json : String, payload : Hash(String, Alumna::AnyData), secret : String = SECRET)
  h = Base64.urlsafe_encode(header_json, padding: false)
  p = Base64.urlsafe_encode(Alumna::JsonHelper.to_string(payload), padding: false)
  signing = "#{h}.#{p}"
  sig = Alumna::JWT.sign(secret.to_slice, signing)
  "#{signing}.#{Base64.urlsafe_encode(sig, padding: false)}"
end

describe Alumna::JWT do
  it "round-trips claims" do
    payload = Alumna.hash(sub: "u1", exp: Time.utc.to_unix + 60)
    token = Alumna::JWT.encode(payload, SECRET)
    result = Alumna::JWT.verify(token, SECRET.to_slice)
    result.should be_a(Hash(String, Alumna::AnyData))
    if result.is_a?(Hash(String, Alumna::AnyData))
      result["sub"].should eq("u1")
    end
  end

  it "rejects an empty secret on encode" do
    expect_raises(ArgumentError, "jwt secret must not be empty") do
      Alumna::JWT.encode(Alumna.hash(sub: "u"), "")
    end
  end

  it "rejects a bad signature" do
    token = Alumna::JWT.encode(Alumna.hash(sub: "u1"), SECRET)
    err = Alumna::JWT.verify(token, "other-secret".to_slice)
    err.should be_a(Alumna::ServiceError)
    if err.is_a?(Alumna::ServiceError)
      err.status.should eq(401)
    end
  end

  it "rejects alg none" do
    token = token_with_header(%({"alg":"none","typ":"JWT"}), Alumna.hash(sub: "u1"))
    err = Alumna::JWT.verify(token, SECRET.to_slice)
    err.should be_a(Alumna::ServiceError)
  end

  it "rejects alg RS256" do
    token = token_with_header(%({"alg":"RS256","typ":"JWT"}), Alumna.hash(sub: "u1"))
    err = Alumna::JWT.verify(token, SECRET.to_slice)
    err.should be_a(Alumna::ServiceError)
  end

  it "rejects an expired token" do
    token = Alumna::JWT.encode(Alumna.hash(exp: Time.utc.to_unix - 30), SECRET)
    err = Alumna::JWT.verify(token, SECRET.to_slice)
    err.should be_a(Alumna::ServiceError)
    if err.is_a?(Alumna::ServiceError)
      err.message.should eq("Token expired")
    end
  end

  it "accepts a near-expiry token when leeway covers it" do
    token = Alumna::JWT.encode(Alumna.hash(exp: Time.utc.to_unix - 2), SECRET)
    result = Alumna::JWT.verify(token, SECRET.to_slice, leeway: 10.seconds)
    result.should be_a(Hash(String, Alumna::AnyData))
  end

  it "rejects nbf in the future" do
    token = Alumna::JWT.encode(Alumna.hash(nbf: Time.utc.to_unix + 60), SECRET)
    err = Alumna::JWT.verify(token, SECRET.to_slice)
    err.should be_a(Alumna::ServiceError)
    if err.is_a?(Alumna::ServiceError)
      err.message.should eq("Unauthorized")
    end
  end

  it "rejects iat in the future" do
    token = Alumna::JWT.encode(Alumna.hash(iat: Time.utc.to_unix + 60), SECRET)
    err = Alumna::JWT.verify(token, SECRET.to_slice)
    err.should be_a(Alumna::ServiceError)
  end

  it "rejects iss mismatch" do
    token = Alumna::JWT.encode(Alumna.hash(iss: "a"), SECRET)
    err = Alumna::JWT.verify(token, SECRET.to_slice, iss: "b")
    err.should be_a(Alumna::ServiceError)
  end

  it "accepts iss match" do
    token = Alumna::JWT.encode(Alumna.hash(iss: "a"), SECRET)
    Alumna::JWT.verify(token, SECRET.to_slice, iss: "a").should be_a(Hash(String, Alumna::AnyData))
  end

  it "matches aud as a string or list" do
    token = Alumna::JWT.encode(Alumna.hash(aud: "api"), SECRET)
    Alumna::JWT.verify(token, SECRET.to_slice, aud: "api").should be_a(Hash(String, Alumna::AnyData))

    list = {"aud" => ["x", "api"].to_any} of String => Alumna::AnyData
    token2 = Alumna::JWT.encode(list, SECRET)
    Alumna::JWT.verify(token2, SECRET.to_slice, aud: "api").should be_a(Hash(String, Alumna::AnyData))

    err = Alumna::JWT.verify(token, SECRET.to_slice, aud: "nope")
    err.should be_a(Alumna::ServiceError)
  end

  it "rejects a truncated token and extra segments" do
    Alumna::JWT.verify("abc", SECRET.to_slice).should be_a(Alumna::ServiceError)
    Alumna::JWT.verify("a.b", SECRET.to_slice).should be_a(Alumna::ServiceError)
    Alumna::JWT.verify("a.b.c.d", SECRET.to_slice).should be_a(Alumna::ServiceError)
    Alumna::JWT.verify(".b.c", SECRET.to_slice).should be_a(Alumna::ServiceError)
    Alumna::JWT.verify("a.b.", SECRET.to_slice).should be_a(Alumna::ServiceError)
    Alumna::JWT.verify("@@@.@@@.@@@", SECRET.to_slice).should be_a(Alumna::ServiceError)
  end

  it "accepts nbf when leeway covers it" do
    token = Alumna::JWT.encode(Alumna.hash(nbf: Time.utc.to_unix + 2), SECRET)
    Alumna::JWT.verify(token, SECRET.to_slice, leeway: 10.seconds).should be_a(Hash(String, Alumna::AnyData))
  end

  it "rejects a truncated JSON payload" do
    h = Base64.urlsafe_encode(%({"alg":"HS256","typ":"JWT"}), padding: false)
    p = Base64.urlsafe_encode("{", padding: false)
    signing = "#{h}.#{p}"
    sig = Alumna::JWT.sign(SECRET.to_slice, signing)
    token = "#{signing}.#{Base64.urlsafe_encode(sig, padding: false)}"
    Alumna::JWT.verify(token, SECRET.to_slice).should be_a(Alumna::ServiceError)
  end

  it "rejects a payload that is not an object" do
    h = Base64.urlsafe_encode(%({"alg":"HS256","typ":"JWT"}), padding: false)
    p = Base64.urlsafe_encode(%(["x"]), padding: false)
    signing = "#{h}.#{p}"
    sig = Alumna::JWT.sign(SECRET.to_slice, signing)
    token = "#{signing}.#{Base64.urlsafe_encode(sig, padding: false)}"
    Alumna::JWT.verify(token, SECRET.to_slice).should be_a(Alumna::ServiceError)
  end
end
