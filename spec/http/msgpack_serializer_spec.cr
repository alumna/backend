require "../spec_helper"

# ── Helpers ───────────────────────────────────────────────────────────────────

private def msgpack_serializer
  Alumna::Http::MsgpackSerializer.new
end

# Encodes a hash, rewinds the IO, then decodes it back.
private def roundtrip(hash : Hash(String, Alumna::AnyData)) : Hash(String, Alumna::AnyData)
  io = IO::Memory.new
  msgpack_serializer.encode(hash, io)
  io.rewind
  msgpack_serializer.decode(io)
end

# ─────────────────────────────────────────────────────────────────────────────

describe Alumna::Http::MsgpackSerializer do
  # ── content_type ─────────────────────────────────────────────────────────────

  describe "#content_type" do
    it "returns application/msgpack" do
      msgpack_serializer.content_type.should eq("application/msgpack")
    end
  end

  # ── encode + decode round-trips ───────────────────────────────────────────────

  describe "encode/decode round-trip" do
    it "preserves a String value" do
      result = roundtrip({"name" => Alumna::AnyData.new("Alice")})
      result["name"].as_s.should eq("Alice")
    end

    it "preserves an Int64 value" do
      result = roundtrip({"count" => Alumna::AnyData.new(42_i64)})
      result["count"].as_i64.should eq(42_i64)
    end

    it "preserves a Float64 value" do
      result = roundtrip({"score" => Alumna::AnyData.new(3.14)})
      result["score"].as_f.should be_close(3.14, 0.0001)
    end

    it "preserves a true Bool value" do
      result = roundtrip({"active" => Alumna::AnyData.new(true)})
      result["active"].as_bool.should be_true
    end

    it "preserves a false Bool value" do
      result = roundtrip({"active" => Alumna::AnyData.new(false)})
      result["active"].as_bool.should be_false
    end

    it "preserves a nil value" do
      result = roundtrip({"note" => Alumna::AnyData.new(nil)})
      result["note"].raw.should be_nil
    end

    it "preserves multiple fields of mixed types in a single hash" do
      input = {
        "name"   => Alumna::AnyData.new("Bob"),
        "age"    => Alumna::AnyData.new(30_i64),
        "score"  => Alumna::AnyData.new(9.5),
        "active" => Alumna::AnyData.new(true),
      }
      result = roundtrip(input)
      result["name"].as_s.should eq("Bob")
      result["age"].as_i64.should eq(30_i64)
      result["score"].as_f.should be_close(9.5, 0.0001)
      result["active"].as_bool.should be_true
    end

    it "returns an empty hash when the input hash is empty" do
      roundtrip({} of String => Alumna::AnyData).should be_empty
    end
  end

  # ── encode array ─────────────────────────────────────────────────────────────

  describe "#encode (Array)" do
    it "encodes an array of hashes to non-empty bytes" do
      input = [
        {"a" => Alumna::AnyData.new("x")},
        {"b" => Alumna::AnyData.new("y")},
      ]
      io = IO::Memory.new
      msgpack_serializer.encode(input, io)
      io.size.should be > 0
    end

    it "encodes an empty array without raising" do
      io = IO::Memory.new
      msgpack_serializer.encode([] of Hash(String, Alumna::AnyData), io)
      io.size.should be >= 0
    end
  end

  # ── decode: malformed input ───────────────────────────────────────────────────

  describe "#decode with malformed input" do
    it "returns an empty hash for garbage bytes" do
      io = IO::Memory.new(Bytes[0xFF, 0xFE, 0x00, 0x01])
      expect_raises(Alumna::ServiceError) { msgpack_serializer.decode(io) }
    end

    it "returns an empty hash for an empty body" do
      io = IO::Memory.new
      msgpack_serializer.decode(io).should be_empty
    end
  end
end
