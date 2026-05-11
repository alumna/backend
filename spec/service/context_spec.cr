require "../spec_helper"
require "../../src/testing"

describe Alumna::RuleContext do
  describe "typed data accessors" do
    it "returns String for data_str?" do
      ctx = Alumna::Testing.build_ctx(data: {"name" => "Alice"} of String => Alumna::AnyData)

      ctx.data_str?("name").should eq("Alice")
      ctx.data_str?("missing").should be_nil
    end

    it "returns Int64 for data_int?" do
      ctx = Alumna::Testing.build_ctx(data: {"age" => 30_i64} of String => Alumna::AnyData)

      ctx.data_int?("age").should eq(30)
      ctx.data_int?("missing").should be_nil
    end

    it "returns Float64 for data_float?" do
      ctx = Alumna::Testing.build_ctx(data: {"score" => 4.5} of String => Alumna::AnyData)

      ctx.data_float?("score").should eq(4.5)
    end

    it "returns Bool for data_bool?" do
      ctx = Alumna::Testing.build_ctx(data: {"active" => true} of String => Alumna::AnyData)

      ctx.data_bool?("active").should be_true
      ctx.data_bool?("missing").should be_nil
    end

    it "returns nil when type mismatches" do
      ctx = Alumna::Testing.build_ctx(data: {"age" => "not-a-number"} of String => Alumna::AnyData)

      ctx.data_int?("age").should be_nil
      ctx.data_bool?("age").should be_nil
    end
  end
end
