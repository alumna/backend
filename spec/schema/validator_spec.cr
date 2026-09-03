require "../spec_helper"

private def empty_data
  Hash(String, Alumna::AnyData).new
end

private def errors_for(schema : Alumna::Schema, input : Hash(String, Alumna::AnyData), method : Alumna::ServiceMethod? = nil)
  schema.validate(input, method)
end

private def error_fields(schema, input, method = nil)
  errors_for(schema, input, method).map(&.field)
end

private def error_on(schema, input, field, method = nil)
  errors_for(schema, input, method).find { |e| e.field == field }.try(&.message)
end

# ─────────────────────────────────────────────────────────────────────────────

describe Alumna::Schema do
  # ── Presence / required ──────────────────────────────────────────────────────

  describe "required fields" do
    schema = Alumna::Schema.new
      .field("name", Alumna::FieldType::Str, required: true)
      .field("note", Alumna::FieldType::Str, required: false)

    it "passes when the required field is present" do
      errors_for(schema, Alumna.hash(name: "Alice")).should be_empty
    end

    it "fails when a required field is absent" do
      error_fields(schema, Alumna.hash(note: "hi")).should contain("name")
    end

    it "fails when a required field is explicitly null" do
      error_fields(schema, Alumna.hash(name: nil)).should contain("name")
    end

    it "does not report an error for a missing optional field" do
      error_fields(schema, Alumna.hash(name: "Alice")).should_not contain("note")
    end

    it "reports the canonical 'is required' message" do
      error_on(schema, Alumna.hash(note: "hi"), "name").should eq("is required")
    end
  end

  # ── required_on with ServiceMethod ───────────────────────────────────────────

  describe "required_on" do
    schema = Alumna::Schema.new
      .str("title", required_on: [:create, :update], min_length: 1)
      .str("content", required: false)

    it "requires title on create" do
      error_fields(schema, empty_data, Alumna::ServiceMethod::Create).should contain("title")
    end

    it "requires title on update" do
      error_fields(schema, empty_data, Alumna::ServiceMethod::Update).should contain("title")
    end

    it "does not require title on patch" do
      errors_for(schema, empty_data, Alumna::ServiceMethod::Patch).should be_empty
    end

    it "does not require title on get" do
      errors_for(schema, empty_data, Alumna::ServiceMethod::Get).should be_empty
    end

    it "requires title when method is nil (backward compatibility)" do
      error_fields(schema, empty_data, nil).should contain("title")
    end

    it "validates constraints only when field is present on patch" do
      errors_for(schema, Alumna.hash(title: ""), Alumna::ServiceMethod::Patch).first.message.should eq("must be at least 1 character")
    end
  end

  describe "Nullability" do
    schema = Alumna::Schema.new
      .str("non_null", nullable: false)
      .str("is_null", nullable: true)
      .any("untyped", nullable: true)

    it "rejects explicit null for non-nullable fields" do
      error_on(schema, Alumna.hash(non_null: nil, is_null: "ok"), "non_null").should eq("cannot be null")
    end

    it "accepts explicit null for nullable fields" do
      errors_for(schema, Alumna.hash(non_null: "ok", is_null: nil, untyped: nil)).should be_empty
    end

    it "allows Any field to accept various types" do
      errors_for(schema, Alumna.hash(non_null: "ok", is_null: nil, untyped: 123_i64)).should be_empty
      errors_for(schema, Alumna.hash(non_null: "ok", is_null: nil, untyped: true)).should be_empty
    end
  end

  describe "Default Value Injection" do
    schema = Alumna::Schema.new
      .int("score", default: 100_i64, required_on: [:create, :update])
      .str("status", default: "active", required_on: [:create, :update])
      .time("created_at", default: -> { Time.utc.as(Alumna::AnyData) }, required_on: [:create, :update])
      .str("note", required: false)

    it "injects defaults during create if field is omitted, waiving required check" do
      data = empty_data
      errs = errors_for(schema, data, Alumna::ServiceMethod::Create)

      errs.should be_empty
      data["score"].should eq(100_i64)
      data["status"].should eq("active")
      data["created_at"].as(Time).should be_close(Time.utc, 1.second)
    end

    it "does NOT inject defaults if client explicitly provides a value" do
      data = Alumna.hash(score: 50_i64, status: "pending")
      errors_for(schema, data, Alumna::ServiceMethod::Create).should be_empty

      data["score"].should eq(50_i64)
      data["status"].should eq("pending")
    end

    it "does NOT inject defaults during patch operations" do
      data = Alumna.hash(note: "updating note only")
      errs = errors_for(schema, data, Alumna::ServiceMethod::Patch)

      errs.should be_empty
      data.has_key?("score").should be_false
      data.has_key?("status").should be_false
    end
  end

  # ── Type checking ─────────────────────────────────────────────────────────────

  describe "Type checking" do
    it "Str type" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Str)
      errors_for(s, Alumna.hash(v: "hello")).should be_empty
      error_on(s, Alumna.hash(v: 1_i64), "v").should eq("must be a string")
      error_on(s, Alumna.hash(v: true), "v").should eq("must be a string")
    end

    it "Int type" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Int)
      errors_for(s, Alumna.hash(v: 42_i64)).should be_empty
      error_on(s, Alumna.hash(v: "42"), "v").should eq("must be an integer")
      error_on(s, Alumna.hash(v: false), "v").should eq("must be an integer")
    end

    it "Float type" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Float)
      errors_for(s, Alumna.hash(v: 3.14)).should be_empty
      errors_for(s, Alumna.hash(v: 3_i64)).should be_empty
      error_on(s, Alumna.hash(v: "3.14"), "v").should eq("must be a number")
    end

    it "Bool type" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Bool)
      errors_for(s, Alumna.hash(v: true)).should be_empty
      errors_for(s, Alumna.hash(v: false)).should be_empty
      error_on(s, Alumna.hash(v: "true"), "v").should eq("must be true or false")
      error_on(s, Alumna.hash(v: 1_i64), "v").should eq("must be true or false")
    end

    it "Time type" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Time)
      errors_for(s, Alumna.hash(v: Time.utc)).should be_empty
      error_on(s, Alumna.hash(v: "2024-01-01"), "v").should eq("must be a time")
    end

    it "Bytes type" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Bytes)
      errors_for(s, Alumna.hash(v: Bytes[1, 2])).should be_empty
      error_on(s, Alumna.hash(v: [1_i64].to_any), "v").should eq("must be bytes")
    end
  end

  # ── String length constraints ─────────────────────────────────────────────────

  describe "min_length" do
    schema = Alumna::Schema.new.field("v", Alumna::FieldType::Str, min_length: 3)

    it "passes when length == min" { errors_for(schema, Alumna.hash(v: "abc")).should be_empty }
    it "passes when length > min" { errors_for(schema, Alumna.hash(v: "abcd")).should be_empty }
    it "fails when length < min" { error_on(schema, Alumna.hash(v: "ab"), "v").should eq("must be at least 3 characters") }
    it "uses singular 'character' for 1" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Str, min_length: 1)
      error_on(s, Alumna.hash(v: ""), "v").should eq("must be at least 1 character")
    end
  end

  describe "max_length" do
    schema = Alumna::Schema.new.field("v", Alumna::FieldType::Str, max_length: 5)

    it "passes when length == max" { errors_for(schema, Alumna.hash(v: "abcde")).should be_empty }
    it "passes when length < max" { errors_for(schema, Alumna.hash(v: "ab")).should be_empty }
    it "fails when length > max" { error_on(schema, Alumna.hash(v: "abcdef"), "v").should eq("must be at most 5 characters") }
    it "uses singular 'character' for 1" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Str, max_length: 1)
      error_on(s, Alumna.hash(v: "ab"), "v").should eq("must be at most 1 character")
    end
  end

  # ── Format constraints ────────────────────────────────────────────────────────

  describe "Email format" do
    schema = Alumna::Schema.new.field("email", Alumna::FieldType::Str, format: :email)

    it "accepts a valid email" { errors_for(schema, Alumna.hash(email: "alice@example.com")).should be_empty }
    it "rejects missing @" { error_on(schema, Alumna.hash(email: "notanemail"), "email").should eq("must be a valid email address") }
  end

  describe "Url format" do
    schema = Alumna::Schema.new.field("url", Alumna::FieldType::Str, format: :url)

    it "accepts https URL" { errors_for(schema, Alumna.hash(url: "https://example.com/path?q=1")).should be_empty }
    it "rejects plain domain" { error_on(schema, Alumna.hash(url: "example.com"), "url").should eq("must be a valid URL (http or https)") }
  end

  describe "Uuid format" do
    schema = Alumna::Schema.new.field("id", Alumna::FieldType::Str, format: :uuid)

    it "accepts a lowercase UUID" { errors_for(schema, Alumna.hash(id: "550e8400-e29b-41d4-a716-446655440000")).should be_empty }
    it "accepts UUID without hyphens" { errors_for(schema, Alumna.hash(id: "550e8400e29b41d4a716446655440000")).should be_empty }
    it "rejects invalid UUID" { error_on(schema, Alumna.hash(id: "550e8400e29b41d4a71644665544"), "id").should eq("must be a valid UUID") }
  end

  describe "ObjectId format" do
    schema = Alumna::Schema.new.field("id", Alumna::FieldType::Str, format: :object_id)

    it "accepts lowercase 24 hex" { errors_for(schema, Alumna.hash(id: "507f1f77bcf86cd799439011")).should be_empty }
    it "accepts uppercase 24 hex" { errors_for(schema, Alumna.hash(id: "507F1F77BCF86CD799439011")).should be_empty }
    it "rejects short hex like AdapterSuite 99" { error_on(schema, Alumna.hash(id: "99"), "id").should eq("must be a valid ObjectId") }
    it "rejects empty" { error_on(schema, Alumna.hash(id: ""), "id").should eq("must be a valid ObjectId") }
    it "rejects odd length" { error_on(schema, Alumna.hash(id: "507f1f77bcf86cd79943901"), "id").should eq("must be a valid ObjectId") }
    it "rejects non-hex" { error_on(schema, Alumna.hash(id: "507f1f77bcf86cd79943901g"), "id").should eq("must be a valid ObjectId") }
  end

  # ── Constraint skipping on type error ────────────────────────────────────────

  describe "skipping length/format checks when type is wrong" do
    schema = Alumna::Schema.new.field("email", Alumna::FieldType::Str,
      min_length: 5,
      format: :email
    )

    it "reports only the type error" do
      errs = errors_for(schema, Alumna.hash(email: 123_i64))
      errs.size.should eq(1)
      errs.first.message.should eq("must be a string")
    end
  end

  describe "edge cases" do
    it "requires an Any field when missing, but accepts null if nullable" do
      schema = Alumna::Schema.new.field("v", Alumna::FieldType::Any, nullable: true, required: true)
      error_fields(schema, empty_data).should contain("v")
      errors_for(schema, Alumna.hash(v: nil)).should be_empty
    end

    it "Int rejects float values" do
      schema = Alumna::Schema.new.field("v", Alumna::FieldType::Int)
      error_on(schema, Alumna.hash(v: 2.5), "v").should eq("must be an integer")
    end

    it "Float rejects bool" do
      schema = Alumna::Schema.new.field("v", Alumna::FieldType::Float)
      error_on(schema, Alumna.hash(v: true), "v").should eq("must be a number")
    end

    it "returns multiple errors for one field" do
      schema = Alumna::Schema.new.field("email", Alumna::FieldType::Str,
        min_length: 10,
        format: :email
      )
      # "a@b" is too short AND fails the email regex (no TLD)
      errs = errors_for(schema, Alumna.hash(email: "a@b"))
      errs.map(&.message).should contain("must be at least 10 characters")
      errs.map(&.message).should contain("must be a valid email address")
      errs.size.should eq(2)
    end

    it "ignores fields not defined in schema when strict is false" do
      schema = Alumna::Schema.new(strict: false).field("name", Alumna::FieldType::Str)
      errors_for(schema, Alumna.hash(name: "ok", extra: "ignored")).should be_empty
    end

    it "accepts uppercase UUID" do
      schema = Alumna::Schema.new.field("id", Alumna::FieldType::Str, format: :uuid)
      errors_for(schema, Alumna.hash(id: "550E8400-E29B-41D4-A716-446655440000")).should be_empty
    end

    it "accepts URL with surrounding whitespace" do
      schema = Alumna::Schema.new.field("u", Alumna::FieldType::Str, format: :url)
      errors_for(schema, Alumna.hash(u: "  https://example.com  ")).should be_empty
    end

    it "rejects URL with internal space" do
      schema = Alumna::Schema.new.field("u", Alumna::FieldType::Str, format: :url)
      error_on(schema, Alumna.hash(u: "https://exa mple.com"), "u").should eq("must be a valid URL (http or https)")
    end

    it "required_on implies presence even when required: false" do
      schema = Alumna::Schema.new.str("title", required: false, required_on: [:create])
      errors_for(schema, empty_data, Alumna::ServiceMethod::Create).first.message.should eq("is required")
      errors_for(schema, empty_data, Alumna::ServiceMethod::Patch).should be_empty
    end
  end

  describe "Nested Fields" do
    it "validates a nested hash object" do
      schema = Alumna::Schema.new.hash("profile") do |s|
        s.str("username", min_length: 3)
        s.int("age")
      end

      # Valid
      valid_data = Alumna.hash(profile: Alumna.hash(username: "Alice", age: 30))
      errors_for(schema, valid_data).should be_empty

      # Invalid nested fields
      invalid_data = Alumna.hash(profile: Alumna.hash(username: "Al", age: "old"))
      errs = errors_for(schema, invalid_data)

      errs.find { |e| e.field == "profile.username" }.try(&.message).should eq("must be at least 3 characters")
      errs.find { |e| e.field == "profile.age" }.try(&.message).should eq("must be an integer")
    end

    it "validates an array of primitives" do
      schema = Alumna::Schema.new.array("tags", of: :str, min_length: 1, max_length: 3)

      # Valid array size & type
      errors_for(schema, Alumna.hash(tags: ["crystal", "alumna"].to_any)).should be_empty

      # Invalid element type
      errs = errors_for(schema, Alumna.hash(tags: ["crystal", 123_i64].to_any))
      errs.first.field.should eq("tags[1]")
      errs.first.message.should eq("must be a string")

      # Invalid array constraints (min_length applied to array size!)
      errs_len = errors_for(schema, Alumna.hash(tags: [] of Alumna::AnyData))
      errs_len.first.field.should eq("tags")
      errs_len.first.message.should eq("must contain at least 1 item")
    end

    it "validates an array of objects" do
      schema = Alumna::Schema.new.array("users") do |s|
        s.str("id")
        s.bool("admin")
      end

      valid_data = Alumna.hash(
        users: [
          Alumna.hash(id: "u1", admin: true),
          Alumna.hash(id: "u2", admin: false),
        ].to_any
      )

      errors_for(schema, valid_data).should be_empty

      invalid_data = Alumna.hash(
        users: [
          Alumna.hash(id: "u1", admin: "yes"),
          "not-an-object".as(Alumna::AnyData),
        ].to_any
      )

      errs = errors_for(schema, invalid_data)
      errs.find { |e| e.field == "users[0].admin" }.try(&.message).should eq("must be true or false")
      errs.find { |e| e.field == "users[1]" }.try(&.message).should eq("must be an object")
    end
  end

  describe "Strict Validation" do
    it "rejects unknown fields by default" do
      schema = Alumna::Schema.new.str("name")
      errs = errors_for(schema, Alumna.hash(name: "Alice", age: 30))
      errs.size.should eq(1)
      errs.first.field.should eq("age")
      errs.first.message.should eq("is not allowed")
    end

    it "cascades strictness to nested hashes" do
      schema = Alumna::Schema.new.hash("profile") do |s|
        s.str("username")
      end
      errs = errors_for(schema, Alumna.hash(profile: Alumna.hash(username: "bob", extra: 1_i64)))
      errs.size.should eq(1)
      errs.first.field.should eq("profile.extra")
      errs.first.message.should eq("is not allowed")
    end

    it "skips reserved $unset path on a strict schema" do
      schema = Alumna::Schema.new.str("name", required: false).str("age", required: false)
      data = Alumna.hash(name: "Alice")
      data["$unset"] = "age"
      errors_for(schema, data, Alumna::ServiceMethod::Patch).should be_empty
      schema.fields.none? { |f| f.name == "$unset" }.should be_true
    end

    it "skips reserved $unset list on a strict schema" do
      schema = Alumna::Schema.new.str("name", required: false).str("age", required: false)
      data = Alumna.hash(name: "Alice")
      data["$unset"] = ["age", "name"] of Alumna::AnyData
      errors_for(schema, data, Alumna::ServiceMethod::Patch).should be_empty
    end

    it "still rejects unknown real fields when $unset is present" do
      schema = Alumna::Schema.new.str("name", required: false)
      data = Alumna.hash(name: "Alice")
      data["$unset"] = "name"
      data["nope"] = "x"
      errs = errors_for(schema, data, Alumna::ServiceMethod::Patch)
      errs.size.should eq(1)
      errs.first.field.should eq("nope")
      errs.first.message.should eq("is not allowed")
    end

    it "still rejects nested $unset as an unknown field" do
      schema = Alumna::Schema.new.hash("profile") do |s|
        s.str("username")
      end
      nested = Alumna.hash(username: "bob")
      nested["$unset"] = "username"
      errs = errors_for(schema, Alumna.hash(profile: nested), Alumna::ServiceMethod::Patch)
      errs.size.should eq(1)
      errs.first.field.should eq("profile.$unset")
      errs.first.message.should eq("is not allowed")
    end
  end

  describe "Read-Only Fields" do
    schema = Alumna::Schema.new
      .str("id", read_only: true)
      .str("name")

    it "allows read-only fields on read operations" do
      errors_for(schema, Alumna.hash(id: "123", name: "Alice"), Alumna::ServiceMethod::Find).should be_empty
    end

    it "rejects read-only fields on create" do
      errs = errors_for(schema, Alumna.hash(id: "123", name: "Alice"), Alumna::ServiceMethod::Create)
      errs.size.should eq(1)
      errs.first.field.should eq("id")
      errs.first.message.should eq("is read-only")
    end

    it "rejects read-only fields on update" do
      errs = errors_for(schema, Alumna.hash(id: "123", name: "Alice"), Alumna::ServiceMethod::Update)
      errs.first.message.should eq("is read-only")
    end

    it "rejects read-only fields on patch" do
      errs = errors_for(schema, Alumna.hash(id: "123", name: "Alice"), Alumna::ServiceMethod::Patch)
      errs.first.message.should eq("is read-only")
    end

    it "allows missing read-only fields on write" do
      errors_for(schema, Alumna.hash(name: "Alice"), Alumna::ServiceMethod::Create).should be_empty
    end
  end
end
