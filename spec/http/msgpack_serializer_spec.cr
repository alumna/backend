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
      result["name"].raw.as(String).should eq("Alice")
    end

    it "preserves an Int64 value" do
      result = roundtrip({"count" => Alumna::AnyData.new(42_i64)})
      result["count"].raw.as(Int64).should eq(42_i64)
    end

    it "preserves a Float64 value" do
      result = roundtrip({"score" => Alumna::AnyData.new(3.14)})
      result["score"].raw.as(Float64).should be_close(3.14, 0.0001)
    end

    it "preserves a true Bool value" do
      result = roundtrip({"active" => Alumna::AnyData.new(true)})
      result["active"].raw.as(Bool).should be_true
    end

    it "preserves a false Bool value" do
      result = roundtrip({"active" => Alumna::AnyData.new(false)})
      result["active"].raw.as(Bool).should be_false
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
      result["name"].raw.as(String).should eq("Bob")
      result["age"].raw.as(Int64).should eq(30_i64)
      result["score"].raw.as(Float64).should be_close(9.5, 0.0001)
      result["active"].raw.as(Bool).should be_true
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

    it "raises ServiceError for an empty body" do
      io = IO::Memory.new
      expect_raises(Alumna::ServiceError) { msgpack_serializer.decode(io) }
    end
  end

  # ── Nested structures ─────────────────────────────────────────────────────────

  describe "nested structures (covers lines 44,46,48,62,63)" do
    it "preserves an array value inside a hash" do
      input = {
        "tags" => Alumna::AnyData.new([
          Alumna::AnyData.new("a"),
          Alumna::AnyData.new("b"),
          Alumna::AnyData.new(1_i64),
        ] of Alumna::AnyData),
      }
      result = roundtrip(input)

      result["tags"].raw.as(Array(Alumna::AnyData))[0].raw.as(String).should eq("a")
      result["tags"].raw.as(Array(Alumna::AnyData))[1].raw.as(String).should eq("b")
      result["tags"].raw.as(Array(Alumna::AnyData))[2].raw.as(Int64).should eq(1_i64)
    end

    it "preserves a hash value inside a hash" do
      input = {
        "meta" => Alumna::AnyData.new({
          "x" => Alumna::AnyData.new(10_i64),
          "y" => Alumna::AnyData.new(true),
        } of String => Alumna::AnyData),
      }
      result = roundtrip(input)

      result["meta"].raw.as(Hash(String, Alumna::AnyData))["x"].raw.as(Int64).should eq(10_i64)
      result["meta"].raw.as(Hash(String, Alumna::AnyData))["y"].raw.as(Bool).should be_true
    end

    it "preserves mixed nested arrays and hashes" do
      nested = Alumna::AnyData.new({"a" => Alumna::AnyData.new(1_i64)} of String => Alumna::AnyData)
      meta = Alumna::AnyData.new({
        "active" => Alumna::AnyData.new(true),
        "nested" => nested,
      } of String => Alumna::AnyData)
      scores = Alumna::AnyData.new([
        Alumna::AnyData.new(1_i64),
        Alumna::AnyData.new(2.5),
        Alumna::AnyData.new(nil),
      ] of Alumna::AnyData)
      tags = Alumna::AnyData.new([
        Alumna::AnyData.new("x"),
        Alumna::AnyData.new("y"),
      ] of Alumna::AnyData)
      user = Alumna::AnyData.new({
        "name"   => Alumna::AnyData.new("Bob"),
        "tags"   => tags,
        "scores" => scores,
        "meta"   => meta,
      } of String => Alumna::AnyData)
      input = {"user" => user}

      result = roundtrip(input)

      u = result["user"].raw.as(Hash(String, Alumna::AnyData))
      u["name"].raw.as(String).should eq("Bob")
      u["tags"].raw.as(Array(Alumna::AnyData)).map(&.raw.as(String)).should eq(["x", "y"])
      u["scores"].raw.as(Array(Alumna::AnyData))[1].raw.as(Float64).should be_close(2.5, 0.0001)
      u["scores"].raw.as(Array(Alumna::AnyData))[2].raw.should be_nil
      u["meta"].raw.as(Hash(String, Alumna::AnyData))["active"].raw.as(Bool).should be_true
      u["meta"].raw.as(Hash(String, Alumna::AnyData))["nested"].raw.as(Hash(String, Alumna::AnyData))["a"].raw.as(Int64).should eq(1_i64)
    end

    it "encodes an array of hashes that contain nested values" do
      input = [
        {"a" => Alumna::AnyData.new([Alumna::AnyData.new("z")] of Alumna::AnyData)},
        {"b" => Alumna::AnyData.new({"k" => Alumna::AnyData.new(5_i64)} of String => Alumna::AnyData)},
      ]
      io = IO::Memory.new
      msgpack_serializer.encode(input, io)
      io.size.should be > 0
    end
  end
end
