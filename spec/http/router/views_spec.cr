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

    it "raises KeyError for missing key on [] but returns nil on []?" do
      src = HTTP::Headers.new
      view = HeadersView.new(src)

      expect_raises(KeyError, /Missing hash key/) do
        view["missing"]
      end

      view["missing"]?.should be_nil
    end

    it "writes to overlay and overrides source" do
      src = HTTP::Headers{"X-Test" => "a"}
      view = HeadersView.new(src)

      view["x-test"] = "b"
      view["x-test"].should eq "b"
      view["x-test"]?.should eq "b"
      src["X-Test"].should eq "a"
    end

    it "iterates overlay first then source, downcasing keys" do
      src = HTTP::Headers{"Content-Type" => "json", "X-Test" => "a"}
      view = HeadersView.new(src)
      view["x-new"] = "b"

      result = {} of String => String
      view.each { |k, v| result[k] = v }

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

    it "iterates source directly when no overlay exists, downcasing keys" do
      src = HTTP::Headers{"Content-Type" => "application/json", "X-Request-Id" => "abc"}
      view = HeadersView.new(src)

      result = {} of String => String
      view.each { |k, v| result[k] = v }

      result.should eq({
        "content-type" => "application/json",
        "x-request-id" => "abc",
      })
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

    it "raises KeyError for missing key on [] but returns nil on []?" do
      src = HTTP::Params.new
      view = ParamsView.new(src)

      expect_raises(KeyError, /Missing hash key/) do
        view["missing"]
      end

      view["missing"]?.should be_nil
    end

    it "iterates source directly when no overlay exists" do
      src = HTTP::Params.parse("x=1&y=2")
      view = ParamsView.new(src)

      result = {} of String => String
      view.each { |k, v| result[k] = v }

      result.should eq({"x" => "1", "y" => "2"})
    end
  end
end
