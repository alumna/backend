require "../../spec_helper"

module Alumna::Http
  describe HeadersView do
    it "reads from source case-insensitively" do
      src = HTTP::Headers{"Content-Type" => "json", "X-Test" => "a"}
      view = HeadersView.new(src)

      view["content-type"].should eq "json"
      view["CONTENT-TYPE"]?.should eq "json"
      view["x-test"].should eq "a"
    end

    it "writes to overlay and overrides source" do
      src = HTTP::Headers{"X-Test" => "a"}
      view = HeadersView.new(src)

      view["x-test"] = "b"          # line 58
      view["x-test"].should eq "b"  # line 50
      view["x-test"]?.should eq "b" # line 54
      src["X-Test"].should eq "a"   # source unchanged
    end

    it "iterates overlay first then source, downcasing keys" do
      src = HTTP::Headers{"Content-Type" => "json", "X-Test" => "a"}
      view = HeadersView.new(src)
      view["x-new"] = "b"

      result = {} of String => String
      view.each { |k, v| result[k] = v } # line 29, line 65

      result.should eq({
        "x-new"        => "b",
        "content-type" => "json",
        "x-test"       => "a",
      })
    end

    it "does not duplicate keys when overlay shadows source" do
      src = HTTP::Headers{"X-Test" => "a"}
      view = HeadersView.new(src)
      view["x-test"] = "b"

      keys = [] of String
      view.each { |k, _| keys << k }

      keys.count("x-test").should eq 1
      keys.first.should eq "x-test"
    end
  end

  describe ParamsView do
    it "reads, writes, and iterates like HeadersView" do
      src = HTTP::Params.parse("a=1&b=2")
      view = ParamsView.new(src)

      view["a"].should eq "1"
      view["c"] = "3"
      view["c"]?.should eq "3"

      result = {} of String => String
      view.each { |k, v| result[k] = v }

      result.should eq({"c" => "3", "a" => "1", "b" => "2"})
    end
  end
end
