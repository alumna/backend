require "../spec_helper"
require "../../src/testing"

# --- 1. Schemas ---
UserSchema = Alumna::Schema.new
  .str("name")

PostSchema = Alumna::Schema.new
  .str("author_id")
  .str("content")

AuditSchema = Alumna::Schema.new
  .str("action")
  .str("resource_id")

# --- 2. Rules ---
AuthenticateGlobal = Alumna::Rule.new do |ctx|
  # If it's an internal call from another service, trust it automatically.
  next nil if ctx.provider == "internal" || ctx.provider == "local"

  token = ctx.headers["authorization"]?
  if token == "Bearer secret-admin"
    # Put the user id in the store. Internal calls will inherit this!
    ctx.store["current_user_id"] = "1"
    nil
  else
    Alumna::ServiceError.unauthorized
  end
end

ValidateAuthorExists = Alumna::Rule.new do |ctx|
  author_id = ctx.data_str?("author_id")

  res, err = ctx.call("/users", :get, id: author_id)
  if err
    next Alumna::ServiceError.unprocessable("Validation failed", Alumna.hash(author_id: "Author does not exist"))
  end
  nil
end

CreateAuditLog = Alumna::Rule.new do |ctx|
  # INTERNAL CALL 2: Fire-and-forget audit log creation
  ctx.call("/audit", :create, Alumna.hash(
    action: "Created Post",
    resource_id: ctx.result.as(Hash)["id"]
  ))

  nil
end

# --- 3. App Setup ---
APP_COMM = Alumna::App.new.tap do |app|
  app.before AuthenticateGlobal

  # Notice how we can use the cleaner syntax here now!
  app.use "/users", Alumna.memory(UserSchema)
  app.use "/audit", Alumna.memory(AuditSchema)

  app.use "/posts", Alumna.memory(PostSchema) {
    before ValidateAuthorExists, on: :create
    after CreateAuditLog, on: :create
  }
end

# --- 4. Specs ---
describe "Inter-Service Communication (ctx.call)" do
  client = Alumna::Testing::AppClient.new(APP_COMM)
  client.default_headers["Authorization"] = "Bearer secret-admin"
  client.default_headers["Content-Type"] = "application/json"

  it "successfully executes an internal call that passes and triggers side-effects" do
    # 1. Create a user via standard HTTP
    res_user = client.post("/users", %({"name":"Alice"}))
    user_id = res_user.json_hash["id"].as(String)

    # 2. Create a post.
    # This will trigger `ValidateAuthorExists` (calls /users)
    # and `CreateAuditLog` (calls /audit).
    res_post = client.post("/posts", %({"author_id":"#{user_id}", "content":"Hello World"}))
    res_post.status.should eq(201)
    post_id = res_post.json_hash["id"].as(String)

    # 3. Verify the Audit service was successfully called internally
    res_audit = client.get("/audit")
    logs = res_audit.json_array

    logs.size.should eq(1)
    logs.first.as(Hash)["action"].should eq("Created Post")
    logs.first.as(Hash)["resource_id"].should eq(post_id)
  end

  it "fails cleanly when an internal call raises an exception" do
    res = client.post("/posts", %({"author_id":"999", "content":"Ghost Post"}))

    res.status.should eq(422)
    res.json_hash.dig_str("details.author_id").should eq("Author does not exist")
  end

  it "propagates the context store to internal calls" do
    # We create an isolated app for this test so we don't violate the `freeze_rules!`
    # lock triggered by the HTTP requests in the previous tests.
    isolated_app = Alumna::App.new

    captured_store_val = nil

    isolated_app.use "/audit", Alumna.memory(Alumna::Schema.new) {
      before do |ctx|
        captured_store_val = ctx.store["current_user_id"]?
        nil
      end
    }

    isolated_app.before AuthenticateGlobal

    isolated_client = Alumna::Testing::AppClient.new(isolated_app)
    isolated_client.default_headers["Authorization"] = "Bearer secret-admin"

    # Trigger a find on audit natively. Since the provider is "rest",
    # the auth rule runs, sets the store, and the audit rule reads it.
    isolated_client.get("/audit")

    captured_store_val.should eq("1")
  end
end
