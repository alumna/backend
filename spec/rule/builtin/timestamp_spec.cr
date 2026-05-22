require "../../spec_helper"
require "../../../src/testing"

describe "Alumna.timestamp" do
  it "injects the current UTC time into the specified field" do
    rule = Alumna.timestamp("created_at")
    res = Alumna::Testing.run_rule(rule)

    res.error.should be_nil
    res.ctx.data.has_key?("created_at").should be_true

    # Assert it's practically 'now'
    res.ctx.data["created_at"].as(Time).should be_close(Time.utc, 1.second)
  end

  it "injects the exact same timestamp instance into multiple fields" do
    rule = Alumna.timestamp("created_at", "updated_at")
    res = Alumna::Testing.run_rule(rule)

    res.error.should be_nil

    t1 = res.ctx.data["created_at"].as(Time)
    t2 = res.ctx.data["updated_at"].as(Time)

    t1.should eq(t2)
    t1.should be_close(Time.utc, 1.second)
  end

  it "overwrites existing values with the new timestamp" do
    rule = Alumna.timestamp("updated_at")

    # Simulate a payload where a client maliciously tried to send an old date
    ctx = Alumna::Testing.build_ctx(
      data: {"updated_at" => Time.utc(2000, 1, 1)} of String => Alumna::AnyData
    )

    res = Alumna::Testing.run_rule(rule, ctx: ctx)

    # Ensure it was forcefully overwritten with 'now'
    res.ctx.data["updated_at"].as(Time).year.should be > 2000
  end
end
