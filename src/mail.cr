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
      raise ArgumentError.new("subject must not be empty") if subject.empty?
      if reply = reply_to
        raise ArgumentError.new("reply_to must not be empty") if reply.empty?
      end

      recipients = recipients_for(to)
      raise ArgumentError.new("to must not be empty") if recipients.empty?
      recipients.each do |address|
        raise ArgumentError.new("to must not be empty") if address.empty?
      end

      @from = from
      @to = recipients
      @subject = subject
      @text = text
      @html = html
      @reply_to = reply_to
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
