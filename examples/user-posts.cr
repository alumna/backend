require "../src/alumna"

UserSchema = Alumna::Schema.new
  .str("name", min_length: 2, max_length: 100)
  .str("email", format: :email)
  .int("age", required: false)

PostSchema = Alumna::Schema.new
  .str("title", required_on: [:create, :update], min_length: 1, max_length: 200)
  .str("body", required_on: [:create, :update], min_length: 1)

Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "Bearer my-secret" ? nil : Alumna::ServiceError.unauthorized
end

app = Alumna::App.new

app.use "/users", Alumna.memory(UserSchema) {
  before Authenticate
  before validate, on: :write
}

app.use "/posts", Alumna.memory(PostSchema) {
  before Authenticate
  before validate, on: :write
}

app.listen(3000)
