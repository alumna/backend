require "../spec_helper"

# ── Helpers ───────────────────────────────────────────────────────────────────

private def json_serializer
  Alumna::Http::JsonSerializer.new
end

# Encodes a hash, rewinds the IO, then decodes it back.
private def roundtrip(hash : Hash(String, Alumna::AnyData)) : Hash(String, Alumna::AnyData)
  io = IO::Memory.new
  json_serializer.encode(hash, io)
  io.rewind
  json_serializer.decode(io).as(Hash(String, Alumna::AnyData))
end

# Encodes a hash and returns the raw JSON string for structural assertions.
private def encode_to_s(hash : Hash(String, Alumna::AnyData)) : String
  io = IO::Memory.new
  json_serializer.encode(hash, io)
  io.to_s
end

# ─────────────────────────────────────────────────────────────────────────────

describe Alumna::Http::JsonSerializer do
  # ── content_type ─────────────────────────────────────────────────────────────

  describe "#content_type" do
    it "returns application/json" do
      json_serializer.content_type.should eq("application/json")
    end
  end

  # ── encode + decode round-trips ───────────────────────────────────────────────

  describe "encode/decode round-trip" do
    it "preserves a String value" do
      result = roundtrip({"name" => "Alice"})
      result["name"].should eq("Alice")
    end

    it "preserves an Int64 value" do
      result = roundtrip({"count" => 42_i64})
      result["count"].should eq(42_i64)
    end

    it "preserves a Float64 value" do
      result = roundtrip({"score" => 3.14})
      result["score"].as(Float64).should be_close(3.14, 0.0001)
    end

    it "preserves a true Bool value" do
      result = roundtrip({"active" => true})
      result["active"].should be_true
    end

    it "preserves a false Bool value" do
      result = roundtrip({"active" => false})
      result["active"].should be_false
    end

    it "preserves a nil value" do
      result = roundtrip({"note" => nil})
      result["note"].should be_nil
    end

    it "preserves multiple fields in a single hash" do
      input = {
        "name"   => "Bob",
        "age"    => 30_i64,
        "active" => true,
      }
      result = roundtrip(input)
      result["name"].should eq("Bob")
      result["age"].should eq(30_i64)
      result["active"].should be_true
    end

    it "returns an empty hash when the input hash is empty" do
      roundtrip({} of String => Alumna::AnyData).should be_empty
    end
  end

  # ── encode array ─────────────────────────────────────────────────────────────

  describe "#encode (Array)" do
    it "encodes an array of hashes to a JSON array" do
      input = [
        {"a" => "x"},
        {"b" => "y"},
      ]
      io = IO::Memory.new
      json_serializer.encode(input, io)
      parsed = JSON.parse(io.to_s)
      parsed.as_a.size.should eq(2)
      parsed.as_a[0]["a"].as_s.should eq("x")
      parsed.as_a[1]["b"].as_s.should eq("y")
    end

    it "encodes an empty array to a JSON empty array" do
      io = IO::Memory.new
      json_serializer.encode([] of Hash(String, Alumna::AnyData), io)
      JSON.parse(io.to_s).as_a.should be_empty
    end
  end

  # ── decode: malformed input ───────────────────────────────────────────────────

  describe "#decode with malformed input" do
    it "returns ServiceError for invalid JSON" do
      io = IO::Memory.new("not valid json")
      result = json_serializer.decode(io)

      result.should be_a(Alumna::ServiceError)
      result.as(Alumna::ServiceError).status.should eq(400)
    end

    it "returns ServiceError for an empty body" do
      io = IO::Memory.new("")
      result = json_serializer.decode(io)

      result.should be_a(Alumna::ServiceError)
      result.as(Alumna::ServiceError).status.should eq(400)
    end
  end
end
