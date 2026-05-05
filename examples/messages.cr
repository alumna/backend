require "../src/alumna"

MessageSchema = Alumna::Schema.new
  .str("body", required: true, min_length: 1, max_length: 500)
  .str("author", required: true, min_length: 1)
  .bool("read", required: false)

Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  if token == "secret-token"
    Alumna::RuleResult.continue
  else
    Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized("Invalid or missing token"))
  end
end

LogResult = Alumna::Rule.new do |ctx|
  puts "[#{ctx.method}] #{ctx.path} → #{ctx.http.status || 200}"
  Alumna::RuleResult.continue
end

class MessageService < Alumna::MemoryAdapter
  def initialize
    super(MessageSchema)
    before Authenticate
    before Alumna.validate(MessageSchema), only: [:create, :update, :patch]
    after LogResult
  end
end

app = Alumna::App.new
app.use("/messages", MessageService.new)
app.listen(3000)
