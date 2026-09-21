module Alumna
  # Send failure from a remote mailer.
  # MemoryMailer never constructs this type.
  # This is not StoreError. StoreError is only for Cache, SessionStore, and RateLimitStore.
  # This is not Exception. send returns it. An app rule can map it to ServiceError.
  struct MailError
    getter message : String

    def initialize(@message : String)
    end

    def to_s(io : IO) : Nil
      io << @message
    end
  end
end
