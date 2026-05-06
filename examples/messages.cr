require "../src/alumna"

MessageSchema = Alumna::Schema.new
  .str("body", min_length: 1, max_length: 500)
  .str("author", min_length: 1)
  .bool("read", required: false)

Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "secret-token" ? nil : Alumna::ServiceError.unauthorized("Invalid or missing token")
end

LogResult = Alumna::Rule.new do |ctx|
  puts "[#{ctx.method}] #{ctx.path} → #{ctx.http.status || 200}"
  nil
end

class MessageService < Alumna::MemoryAdapter
  def initialize
    super(MessageSchema)
    before Authenticate
    before Alumna.validate(MessageSchema), on: :write
    after LogResult
  end
end

app = Alumna::App.new
app.use("/messages", MessageService.new)
app.listen(3000)
