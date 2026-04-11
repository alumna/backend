# examples/messages.cr
require "../src/alumna"

# ── 1. Schema ──────────────────────────────────────────────────────────────────
# Describes the shape of a message. The adapter reads .fields to know
# what to store; rules call schema.validate(data) for input checking.

MessageSchema = Alumna::Schema.new
  .field("body", Alumna::FieldType::Str, required: true, min_length: 1, max_length: 500)
  .field("author", Alumna::FieldType::Str, required: true, min_length: 1)
  .field("read", Alumna::FieldType::Bool, required: false)

# ── 2. Rules ───────────────────────────────────────────────────────────────────
# Each rule is a named Proc constant. It receives a context, returns a
# RuleResult. Rules do not call each other; the orchestrator sequences them.

module Rules
  # Simulates token authentication. In a real app, ctx.params["authorization"]
  # would be checked against a session or JWT.
  Authenticate = Alumna::Rule.new do |ctx|
    token = ctx.headers["authorization"]?
    if token == "secret-token"
      Alumna::RuleResult.continue
    else
      Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized("Invalid or missing token"))
    end
  end

  # Validates that the request body matches the MessageSchema.
  # Only makes sense on writes, so it will be registered with only: [...].
  ValidateMessage = Alumna::Rule.new do |ctx|
    errors = MessageSchema.validate(ctx.data)
    if errors.empty?
      Alumna::RuleResult.continue
    else
      details = errors.each_with_object({} of String => String) do |e, h|
        h[e.field] = e.message
      end
      Alumna::RuleResult.stop(Alumna::ServiceError.unprocessable("Validation failed", details))
    end
  end

  # Logs every request to stdout. An example of a lightweight after-rule.
  LogResult = Alumna::Rule.new do |ctx|
    puts "[#{ctx.method}] #{ctx.path} → #{ctx.http.status || 200}"
    Alumna::RuleResult.continue
  end
end

# ── 3. Service ─────────────────────────────────────────────────────────────────
# MessageService inherits MemoryAdapter (which already implements all abstract
# service methods). It only needs to wire up its rules.

class MessageService < Alumna::MemoryAdapter
  def initialize
    super("/messages", MessageSchema)

    # Authenticate every request, regardless of method
    self.before(Rules::Authenticate)

    # Validate body only on writes
    self.before(
      Rules::ValidateMessage,
      only: [
        Alumna::ServiceMethod::Create,
        Alumna::ServiceMethod::Update,
        Alumna::ServiceMethod::Patch,
      ]
    )

    # Log after every successful response
    self.after(Rules::LogResult)
  end
end

# ── 4. App ─────────────────────────────────────────────────────────────────────

app = Alumna::App.new
app.use("/messages", MessageService.new)
app.listen(3000)
