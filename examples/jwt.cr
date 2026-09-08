require "../src/alumna"

UserSchema = Alumna::Schema.new
  .str("email", format: :email)
  .str("name", min_length: 1)

Secret = "change-me"

app = Alumna::App.new
app.before Alumna.logger
app.after Alumna.logger

app.use "/login", Alumna.memory(Alumna::Schema.new) {
  after on: :create do |ctx|
    token = Alumna::JWT.encode(
      Alumna.hash(sub: "1", exp: (Time.utc + 24.hours).to_unix),
      Secret
    )
    ctx.result = Alumna.hash(token: token)
    nil
  end
}

app.use "/users", Alumna.memory(UserSchema) {
  before Alumna.jwt(Secret)
  before validate, on: :write
}

app.listen(3000)
