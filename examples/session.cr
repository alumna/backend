require "../src/alumna"

UserSchema = Alumna::Schema.new
  .str("email", format: :email)
  .str("name", min_length: 1)

store = Alumna::MemorySessionStore.new(ttl: 24.hours)
sessions = Alumna::Session.new(store, secure: false)

app = Alumna::App.new
app.before Alumna.logger
app.after Alumna.logger

app.use "/login", Alumna.memory(Alumna::Schema.new) {
  after on: :create do |ctx|
    sessions.start(ctx, Alumna.hash(user_id: "1"))
    nil
  end
}

app.use "/users", Alumna.memory(UserSchema) {
  before sessions.rule
  before validate, on: :write
}

app.use "/logout", Alumna.memory(Alumna::Schema.new) {
  before sessions.rule
  after on: :create do |ctx|
    sessions.stop(ctx)
    nil
  end
}

app.listen(3000)
