require "../spec_helper"

describe Alumna::Mail do
  it "keeps one recipient and the optional fields" do
    mail = Alumna::Mail.new(
      from: "from@example.com",
      to: "to@example.com",
      subject: "Hello",
      text: "Plain",
      html: "<p>Plain</p>",
      reply_to: "reply@example.com",
    )
    mail.from.should eq("from@example.com")
    mail.to.should eq(["to@example.com"])
    mail.subject.should eq("Hello")
    mail.text.should eq("Plain")
    mail.html.should eq("<p>Plain</p>")
    mail.reply_to.should eq("reply@example.com")
  end

  it "keeps several recipients in order" do
    mail = Alumna::Mail.new(
      from: "from@example.com",
      to: ["a@example.com", "b@example.com"],
      subject: "Hello",
      text: "Plain",
    )
    mail.to.should eq(["a@example.com", "b@example.com"])
    mail.html.should be_nil
    mail.reply_to.should be_nil
  end

  it "allows an empty text body" do
    mail = Alumna::Mail.new(
      from: "from@example.com",
      to: "to@example.com",
      subject: "Hello",
      text: "",
    )
    mail.text.should eq("")
  end

  it "copies the recipient list" do
    recipients = ["a@example.com"]
    mail = Alumna::Mail.new(
      from: "from@example.com",
      to: recipients,
      subject: "Hello",
      text: "Plain",
    )
    recipients << "other@example.com"
    mail.to.should eq(["a@example.com"])
  end

  it "rejects an empty from" do
    expect_raises(ArgumentError, "from must not be empty") do
      Alumna::Mail.new(from: "", to: "to@example.com", subject: "Hello", text: "Plain")
    end
  end

  it "rejects an empty subject" do
    expect_raises(ArgumentError, "subject must not be empty") do
      Alumna::Mail.new(from: "from@example.com", to: "to@example.com", subject: "", text: "Plain")
    end
  end

  it "rejects an empty recipient string" do
    expect_raises(ArgumentError, "to must not be empty") do
      Alumna::Mail.new(from: "from@example.com", to: "", subject: "Hello", text: "Plain")
    end
  end

  it "rejects an empty recipient list" do
    expect_raises(ArgumentError, "to must not be empty") do
      Alumna::Mail.new(from: "from@example.com", to: [] of String, subject: "Hello", text: "Plain")
    end
  end

  it "rejects an empty address in the recipient list" do
    expect_raises(ArgumentError, "to must not be empty") do
      Alumna::Mail.new(
        from: "from@example.com",
        to: ["ok@example.com", ""],
        subject: "Hello",
        text: "Plain",
      )
    end
  end

  it "rejects a CR or LF in from" do
    expect_raises(ArgumentError, "from must not contain CR or LF") do
      Alumna::Mail.new(from: "a@example.com\r\nBcc: x@example.com", to: "to@example.com", subject: "Hello", text: "Plain")
    end
    expect_raises(ArgumentError, "from must not contain CR or LF") do
      Alumna::Mail.new(from: "a@example.com\n", to: "to@example.com", subject: "Hello", text: "Plain")
    end
  end

  it "rejects a CR or LF in subject" do
    expect_raises(ArgumentError, "subject must not contain CR or LF") do
      Alumna::Mail.new(from: "from@example.com", to: "to@example.com", subject: "Hello\rBcc: x@example.com", text: "Plain")
    end
  end

  it "rejects a CR or LF in a recipient" do
    expect_raises(ArgumentError, "to must not contain CR or LF") do
      Alumna::Mail.new(from: "from@example.com", to: "to@example.com\n", subject: "Hello", text: "Plain")
    end
    expect_raises(ArgumentError, "to must not contain CR or LF") do
      Alumna::Mail.new(
        from: "from@example.com",
        to: ["ok@example.com", "bad@example.com\r\nRCPT TO:<x@example.com>"],
        subject: "Hello",
        text: "Plain",
      )
    end
  end

  it "rejects a CR or LF in reply_to" do
    expect_raises(ArgumentError, "reply_to must not contain CR or LF") do
      Alumna::Mail.new(
        from: "from@example.com",
        to: "to@example.com",
        subject: "Hello",
        text: "Plain",
        reply_to: "reply@example.com\r\n",
      )
    end
  end

  it "keeps line breaks in text and html" do
    mail = Alumna::Mail.new(
      from: "from@example.com",
      to: "to@example.com",
      subject: "Hello",
      text: "one\r\ntwo\n",
      html: "<p>one</p>\n<p>two</p>",
    )
    mail.text.should eq("one\r\ntwo\n")
    mail.html.should eq("<p>one</p>\n<p>two</p>")
  end

  it "accepts a display name with the address" do
    mail = Alumna::Mail.new(
      from: "Alumna <from@example.com>",
      to: "User <to@example.com>",
      subject: "Olá",
      text: "Plain",
    )
    mail.from.should eq("Alumna <from@example.com>")
    mail.to.should eq(["User <to@example.com>"])
  end

  it "rejects an empty reply_to" do
    expect_raises(ArgumentError, "reply_to must not be empty") do
      Alumna::Mail.new(
        from: "from@example.com",
        to: "to@example.com",
        subject: "Hello",
        text: "Plain",
        reply_to: "",
      )
    end
  end
end
