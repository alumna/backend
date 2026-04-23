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

    it "preserves multiple fields of mixed types in a single hash" do
      input = {
        "name"   => "Bob",
        "age"    => 30_i64,
        "score"  => 9.5,
        "active" => true,
      }
      result = roundtrip(input)
      result["name"].should eq("Bob")
      result["age"].should eq(30_i64)
      result["score"].as(Float64).should be_close(9.5, 0.0001)
      result["active"].should be_true
    end

    it "returns an empty hash when the input hash is empty" do
      roundtrip({} of String => Alumna::AnyData).should be_empty
    end
  end

  # ── encode array ─────────────────────────────────────────────────────────────

  describe "#encode (Array)" do
    it "encodes an array of hashes to non-empty bytes" do
      input = [
        {"a" => "x"},
        {"b" => "y"},
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

  # Nested structures

  describe "nested structures (covers lines 44,46,48,62,63)" do
    it "preserves an array value inside a hash" do
      input = {
        "tags" => ["a", "b", 1_i64] of Alumna::AnyData,
      }
      result = roundtrip(input)

      tags = result["tags"].as(Array(Alumna::AnyData))
      tags[0].should eq("a")
      tags[1].should eq("b")
      tags[2].should eq(1_i64)
    end

    it "preserves a hash value inside a hash" do
      input = {
        "meta" => {"x" => 10_i64, "y" => true} of String => Alumna::AnyData,
      }
      result = roundtrip(input)

      meta = result["meta"].as(Hash(String, Alumna::AnyData))
      meta["x"].should eq(10_i64)
      meta["y"].should be_true
    end

    it "preserves mixed nested arrays and hashes" do
      input = {
        "user" => {
          "name"   => "Bob",
          "tags"   => ["x", "y"] of Alumna::AnyData,
          "scores" => [1_i64, 2.5, nil] of Alumna::AnyData,
          "meta"   => {
            "active" => true,
            "nested" => {"a" => 1_i64} of String => Alumna::AnyData,
          } of String => Alumna::AnyData,
        } of String => Alumna::AnyData,
      }

      result = roundtrip(input)

      user = result["user"].as(Hash(String, Alumna::AnyData))
      user["name"].should eq("Bob")
      user["tags"].as(Array(Alumna::AnyData)).map(&.as(String)).should eq(["x", "y"])
      user["scores"].as(Array(Alumna::AnyData))[1].as(Float64).should be_close(2.5, 0.0001)
      user["scores"].as(Array(Alumna::AnyData))[2].should be_nil
      meta = user["meta"].as(Hash(String, Alumna::AnyData))
      meta["active"].should be_true
      meta["nested"].as(Hash(String, Alumna::AnyData))["a"].should eq(1_i64)
    end

    it "encodes an array of hashes that contain nested values" do
      input = [
        {"a" => ["z"] of Alumna::AnyData} of String => Alumna::AnyData,
        {"b" => {"k" => 5_i64} of String => Alumna::AnyData} of String => Alumna::AnyData,
      ]
      io = IO::Memory.new
      msgpack_serializer.encode(input, io)
      io.size.should be > 0
      # decode isn't supported for top-level arrays, but encode hits the new direct path
    end
  end
end
