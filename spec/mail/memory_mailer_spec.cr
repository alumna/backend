require "../spec_helper"
require "wait_group"

private def sample_mail(to : String = "to@example.com", text : String = "Plain") : Alumna::Mail
  Alumna::Mail.new(
    from: "from@example.com",
    to: to,
    subject: "Hello",
    text: text,
    html: "<p>Plain</p>",
    reply_to: "reply@example.com",
  )
end

describe Alumna::MemoryMailer do
  it "records a message and returns nil" do
    mailer = Alumna::MemoryMailer.new
    result = mailer.send(sample_mail)
    result.should be_nil

    delivered = mailer.delivered
    delivered.size.should eq(1)
    delivered[0].from.should eq("from@example.com")
    delivered[0].to.should eq(["to@example.com"])
    delivered[0].subject.should eq("Hello")
    delivered[0].text.should eq("Plain")
    delivered[0].html.should eq("<p>Plain</p>")
    delivered[0].reply_to.should eq("reply@example.com")
  end

  it "returns nil through the Mailer port" do
    mailer = Alumna::MemoryMailer.new.as(Alumna::Mailer)
    mailer.send(sample_mail).should be_nil
  end

  it "keeps send order" do
    mailer = Alumna::MemoryMailer.new
    mailer.send(sample_mail("a@example.com", "one"))
    mailer.send(sample_mail("b@example.com", "two"))
    mailer.delivered.map(&.text).should eq(["one", "two"])
  end

  it "stores a copy and returns a copy" do
    mailer = Alumna::MemoryMailer.new
    mail = sample_mail
    mailer.send(mail)
    mail.to << "later@example.com"
    mail.to[0] = "changed@example.com"

    first = mailer.delivered
    first[0].to.should eq(["to@example.com"])
    first[0].to << "mutated@example.com"
    first[0].to[0] = "also@example.com"

    mailer.delivered[0].to.should eq(["to@example.com"])
  end

  it "records sends from many fibers" do
    mailer = Alumna::MemoryMailer.new
    WaitGroup.wait do |wg|
      32.times do |index|
        wg.spawn do
          mailer.send(sample_mail("user#{index}@example.com"))
        end
      end
    end
    delivered = mailer.delivered
    delivered.size.should eq(32)
    delivered.map(&.to[0]).sort.should eq((0...32).map { |index| "user#{index}@example.com" }.sort)
  end
end
