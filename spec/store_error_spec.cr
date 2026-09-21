require "./spec_helper"

describe Alumna::StoreError do
  it "exposes the message and writes it to an IO" do
    err = Alumna::StoreError.new("cache down")
    err.message.should eq("cache down")
    err.to_s.should eq("cache down")
  end
end
