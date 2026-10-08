require "../spec_helper"

describe Alumna::JsonHelper do
  describe ".to_string" do
    it "conveniently serializes AnyData to a JSON string for adapters" do
      data = {"name" => "Alice", "age" => 30_i64} of String => Alumna::AnyData

      json_str = Alumna::JsonHelper.to_string(data)
      json_str.should eq(%({"name":"Alice","age":30}))
    end

    it "matches JSON::Builder for the supported values" do
      data = rich_json
      io = IO::Memory.new
      Alumna::JsonHelper.write(io, data)
      io.to_s.should eq(Alumna::JsonHelper.to_string(data))

      built = JSON.build { |builder| Alumna::JsonHelper.encode(data, builder) }
      built.should eq(Alumna::JsonHelper.to_string(data))
    end

    it "rejects a non-finite float" do
      expect_raises(JSON::Error, "NaN not allowed in JSON") do
        Alumna::JsonHelper.to_string(Float64::NAN)
      end
      expect_raises(JSON::Error, "Infinity not allowed in JSON") do
        Alumna::JsonHelper.to_string(Float64::INFINITY)
      end
    end
  end

  describe ".from_string" do
    it "conveniently deserializes a JSON string into AnyData for adapters" do
      json_str = %({"active":true,"tags":["crystal","alumna"]})

      result = Alumna::JsonHelper.from_string(json_str).as(Hash(String, Alumna::AnyData))
      result["active"].should be_true
      result["tags"].as(Array(Alumna::AnyData)).should eq(["crystal", "alumna"])
    end
  end
end

def rich_json : Hash(String, Alumna::AnyData)
  data = {} of String => Alumna::AnyData
  data["name"] = "a\"b\\c\b\f\n\r\t\u0001\u007f"
  data["n"] = 0_i64
  data["neg"] = -2_i64
  data["f"] = 1.5
  data["ok"] = true
  data["no"] = false
  data["empty"] = nil
  data["when"] = Time.utc(2026, 10, 7, 21, 0, 0)
  data["bin"] = Bytes[1, 2, 255]
  data["none_bin"] = Bytes.empty
  list = [] of Alumna::AnyData
  list << "v"
  list << 2_i64
  data["list"] = list
  data["obj"] = {} of String => Alumna::AnyData
  data["none"] = [] of Alumna::AnyData
  data
end
