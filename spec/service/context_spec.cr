require "../spec_helper"
require "../../src/testing"

private class DummyUser
  include Alumna::Storeable
  property name : String

  def initialize(@name)
  end
end

private struct DummyTransaction
  include Alumna::Storeable
  property id : Int32

  def initialize(@id)
  end
end

describe Alumna::RuleContext do
  describe "store" do
    it "can store and retrieve arbitrary classes (Reference) via Storeable" do
      ctx = Alumna::Testing.build_ctx
      user = DummyUser.new("Alice")
      ctx.store["user"] = user
      retrieved = ctx.store["user"].as(DummyUser)
      retrieved.name.should eq("Alice")
    end

    it "can store and retrieve arbitrary structs (Value) via Storeable" do
      ctx = Alumna::Testing.build_ctx
      tx = DummyTransaction.new(42)
      ctx.store["tx"] = tx
      retrieved = ctx.store["tx"].as(DummyTransaction)
      retrieved.id.should eq(42)
    end

    it "can store and retrieve AnyData types without compile errors" do
      ctx = Alumna::Testing.build_ctx
      ctx.store["count"] = 100_i64
      ctx.store["flag"] = true

      ctx.store["count"].as(Int64).should eq(100)
      ctx.store["flag"].as(Bool).should be_true
    end
  end

  describe "result handling" do
    it "is not set initially" do
      ctx = Alumna::Testing.build_ctx
      ctx.result_set?.should be_false
      ctx.result.should be_nil
    end

    it "is set when explicitly assigned nil" do
      ctx = Alumna::Testing.build_ctx
      ctx.result = nil
      ctx.result_set?.should be_true
      ctx.result.should be_nil
    end

    it "is set when assigned a Hash" do
      ctx = Alumna::Testing.build_ctx
      ctx.result = {"ok" => true} of String => Alumna::AnyData
      ctx.result_set?.should be_true
    end
  end

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
