require "../spec_helper"

describe Alumna::JsonHelper do
  describe ".to_string" do
    it "conveniently serializes AnyData to a JSON string for adapters" do
      data = {"name" => "Alice", "age" => 30_i64} of String => Alumna::AnyData

      json_str = Alumna::JsonHelper.to_string(data)
      json_str.should eq(%({"name":"Alice","age":30}))
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
