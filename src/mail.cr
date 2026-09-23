require "./mail/error"

module Alumna
  # One outbound message. The app builds it and passes it to Mailer#send.
  # There is no built-in mail rule in this release.
  #
  # `to` accepts one address or a list. The struct keeps its own list.
  # A later change to the caller's array does not change this mail.
  #
  # Empty from, empty to, or empty subject raises ArgumentError.
  # An empty address in `to` raises ArgumentError.
  # An empty `reply_to` raises ArgumentError. Omit `reply_to` when there is none.
  #
  # A CR or LF in from, subject, reply_to, or an address in `to` raises ArgumentError.
  # These values go into mail headers and SMTP commands. A line break there lets
  # a caller add headers or commands (header injection). `text` and `html` can
  # contain line breaks. An adapter encodes the body.
  struct Mail
    getter from : String
    getter to : Array(String)
    getter subject : String
    getter text : String
    getter html : String?
    getter reply_to : String?

    def initialize(
      *,
      from : String,
      to : String | Array(String),
      subject : String,
      text : String,
      html : String? = nil,
      reply_to : String? = nil,
    )
      raise ArgumentError.new("from must not be empty") if from.empty?
      raise ArgumentError.new("from must not contain CR or LF") if line_break?(from)
      raise ArgumentError.new("subject must not be empty") if subject.empty?
      raise ArgumentError.new("subject must not contain CR or LF") if line_break?(subject)
      if reply = reply_to
        raise ArgumentError.new("reply_to must not be empty") if reply.empty?
        raise ArgumentError.new("reply_to must not contain CR or LF") if line_break?(reply)
      end

      recipients = recipients_for(to)
      raise ArgumentError.new("to must not be empty") if recipients.empty?
      recipients.each do |address|
        raise ArgumentError.new("to must not be empty") if address.empty?
        raise ArgumentError.new("to must not contain CR or LF") if line_break?(address)
      end

      @from = from
      @to = recipients
      @subject = subject
      @text = text
      @html = html
      @reply_to = reply_to
    end

    # True when the value has a CR or LF byte. One pass over the bytes, no allocation.
    private def line_break?(value : String) : Bool
      value.each_byte { |byte| return true if byte == 13_u8 || byte == 10_u8 }
      false
    end

    # One address becomes a one-element list. A list is copied.
    private def recipients_for(to : String | Array(String)) : Array(String)
      if to.is_a?(String)
        [to]
      else
        to.dup
      end
    end
  end

  # Port for one in-process send.
  # MemoryMailer records the message. A remote mailer (SES) performs the send.
  # Success is nil. Failure is MailError. MemoryMailer never returns MailError.
  # Empty from, to, or subject fails in Mail.new before send.
  abstract class Mailer
    abstract def send(mail : Mail) : Nil | MailError
  end
end

require "./mail/memory"
