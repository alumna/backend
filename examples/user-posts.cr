require "../src/alumna"

UserSchema = Alumna::Schema.new
  .str("name", required: true, min_length: 2, max_length: 100)
  .str("email", required: true, format: :email)
  .int("age", required: false)

PostSchema = Alumna::Schema.new
  .str("title", required_on: [:create, :update], min_length: 1, max_length: 200)
  .str("body", required_on: [:create, :update], min_length: 1)

Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "Bearer my-secret" ? nil : Alumna::ServiceError.unauthorized
end

class UserService < Alumna::MemoryAdapter
  def initialize
    super(UserSchema)
    before Authenticate
    before Alumna.validate(UserSchema), on: :write
  end
end

class PostService < Alumna::MemoryAdapter
  def initialize
    super(PostSchema)
    before Authenticate
    before Alumna.validate(PostSchema), on: :write
  end
end

app = Alumna::App.new
app.use("/users", UserService.new)
app.use("/posts", PostService.new)
app.listen(3000)
