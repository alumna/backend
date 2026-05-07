require "../spec_helper"

describe Alumna::RuleContext do
  describe "typed data accessors" do
    it "returns String for data_str?" do
      ctx = test_ctx
      ctx.data["name"] = "Alice"
      ctx.data_str?("name").should eq("Alice")
      ctx.data_str?("missing").should be_nil
    end

    it "returns Int64 for data_int?" do
      ctx = test_ctx
      ctx.data["age"] = 30_i64
      ctx.data_int?("age").should eq(30)
      ctx.data_int?("missing").should be_nil
    end

    it "returns Float64 for data_float?" do
      ctx = test_ctx
      ctx.data["score"] = 4.5
      ctx.data_float?("score").should eq(4.5)
    end

    it "returns Bool for data_bool?" do
      ctx = test_ctx
      ctx.data["active"] = true
      ctx.data_bool?("active").should be_true
      ctx.data_bool?("missing").should be_nil
    end

    it "returns nil when type mismatches" do
      ctx = test_ctx
      ctx.data["age"] = "not-a-number"
      ctx.data_int?("age").should be_nil
      ctx.data_bool?("age").should be_nil
    end
  end
end
