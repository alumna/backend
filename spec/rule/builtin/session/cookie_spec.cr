require "../../../spec_helper"

describe Alumna::Http do
  describe ".cookie_value" do
    it "returns nil for an empty name" do
      Alumna::Http.cookie_value("a=1", "").should be_nil
    end

    it "returns nil for an empty header" do
      Alumna::Http.cookie_value("", "sid").should be_nil
    end

    it "returns nil when the header has no match" do
      Alumna::Http.cookie_value("a=1; b=2", "alumna.sid").should be_nil
    end

    it "reads a lone cookie" do
      Alumna::Http.cookie_value("alumna.sid=abc", "alumna.sid").should eq("abc")
    end

    it "reads a cookie among others" do
      Alumna::Http.cookie_value("a=1; alumna.sid=xyz; b=2", "alumna.sid").should eq("xyz")
    end

    it "does not match a suffix of another name" do
      Alumna::Http.cookie_value("xalumna.sid=no; alumna.sid=yes", "alumna.sid").should eq("yes")
    end

    it "returns the first value when the name repeats" do
      Alumna::Http.cookie_value("sid=one; sid=two", "sid").should eq("one")
    end

    it "skips spaces after a semicolon" do
      Alumna::Http.cookie_value("a=1;  sid=z", "sid").should eq("z")
    end

    it "returns an empty value" do
      Alumna::Http.cookie_value("sid=", "sid").should eq("")
    end
  end
end
