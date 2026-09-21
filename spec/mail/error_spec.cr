require "../spec_helper"

describe Alumna::MailError do
  it "exposes the message and writes it to an IO" do
    err = Alumna::MailError.new("ses rejected the message")
    err.message.should eq("ses rejected the message")
    err.to_s.should eq("ses rejected the message")
  end
end
