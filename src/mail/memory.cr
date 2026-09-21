require "mutex"

module Alumna
  # In-process mailer. Use it in specs and in a single process that only records mail.
  # Swap for Alumna::SES when the app must deliver.
  #
  # send copies the message under a Sync::Mutex. delivered returns new copies.
  # A change to a returned Mail, or to the Mail passed to send, does not change the store.
  # This mailer never returns MailError.
  class MemoryMailer < Mailer
    def initialize
      @messages = [] of Mail
      @mutex = Sync::Mutex.new
    end

    def send(mail : Mail) : Nil
      stored = copy(mail)
      @mutex.synchronize { @messages << stored }
    end

    # Copies of every message accepted by send, in send order.
    def delivered : Array(Mail)
      @mutex.synchronize do
        @messages.map { |mail| copy(mail) }
      end
    end

    private def copy(mail : Mail) : Mail
      Mail.new(
        from: mail.from,
        to: mail.to,
        subject: mail.subject,
        text: mail.text,
        html: mail.html,
        reply_to: mail.reply_to,
      )
    end
  end
end
