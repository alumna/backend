require "../spec_helper"

# Helpers to build AnyData values without boilerplate
private def any(v : String)
  JSON::Any.new(v)
end

private def any(v : Int64)
  JSON::Any.new(v)
end

private def any(v : Float64)
  JSON::Any.new(v)
end

private def any(v : Bool)
  JSON::Any.new(v)
end

private def any_nil
  JSON::Any.new(nil)
end

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
      errors_for(schema, {"name" => any("Alice")}).should be_empty
    end

    it "fails when a required field is absent" do
      error_fields(schema, {"note" => any("hi")}).should contain("name")
    end

    it "fails when a required field is explicitly null" do
      error_fields(schema, {"name" => any_nil}).should contain("name")
    end

    it "does not report an error for a missing optional field" do
      error_fields(schema, {"name" => any("Alice")}).should_not contain("note")
    end

    it "reports the canonical 'is required' message" do
      error_on(schema, {"note" => any("hi")}, "name").should eq("is required")
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
      # title missing on patch = ok, but if provided empty, min_length fails
      errors_for(schema, {"title" => any("")}, Alumna::ServiceMethod::Patch).first.message.should eq("must be at least 1 character")
    end
  end

  # ── Type checking ─────────────────────────────────────────────────────────────

  describe "Str type" do
    schema = Alumna::Schema.new.field("v", Alumna::FieldType::Str)

    it "accepts a string" { errors_for(schema, {"v" => any("hello")}).should be_empty }
    it "rejects an integer" { error_on(schema, {"v" => any(1_i64)}, "v").should eq("must be a string") }
    it "rejects a bool" { error_on(schema, {"v" => any(true)}, "v").should eq("must be a string") }
  end

  describe "Int type" do
    schema = Alumna::Schema.new.field("v", Alumna::FieldType::Int)

    it "accepts an integer" { errors_for(schema, {"v" => any(42_i64)}).should be_empty }
    it "rejects a string" { error_on(schema, {"v" => any("42")}, "v").should eq("must be an integer") }
    it "rejects a bool" { error_on(schema, {"v" => any(false)}, "v").should eq("must be an integer") }
  end

  describe "Float type" do
    schema = Alumna::Schema.new.field("v", Alumna::FieldType::Float)

    it "accepts a float" { errors_for(schema, {"v" => any(3.14)}).should be_empty }
    it "accepts an integer (coercible)" { errors_for(schema, {"v" => any(3_i64)}).should be_empty }
    it "rejects a string" { error_on(schema, {"v" => any("3.14")}, "v").should eq("must be a number") }
  end

  describe "Bool type" do
    schema = Alumna::Schema.new.field("v", Alumna::FieldType::Bool)

    it "accepts true" { errors_for(schema, {"v" => any(true)}).should be_empty }
    it "accepts false" { errors_for(schema, {"v" => any(false)}).should be_empty }
    it "rejects a string" { error_on(schema, {"v" => any("true")}, "v").should eq("must be true or false") }
    it "rejects an int" { error_on(schema, {"v" => any(1_i64)}, "v").should eq("must be true or false") }
  end

  describe "Nullable type" do
    schema = Alumna::Schema.new.field("v", Alumna::FieldType::Nullable, required: false)

    it "accepts any value when present" do
      errors_for(schema, {"v" => any("anything")}).should be_empty
      errors_for(schema, {"v" => any(1_i64)}).should be_empty
      errors_for(schema, {"v" => any(true)}).should be_empty
    end

    it "does not require the field" do
      errors_for(schema, empty_data).should be_empty
    end
  end

  # ── String length constraints ─────────────────────────────────────────────────

  describe "min_length" do
    schema = Alumna::Schema.new.field("v", Alumna::FieldType::Str, min_length: 3)

    it "passes when length == min" { errors_for(schema, {"v" => any("abc")}).should be_empty }
    it "passes when length > min" { errors_for(schema, {"v" => any("abcd")}).should be_empty }
    it "fails when length < min" { error_on(schema, {"v" => any("ab")}, "v").should eq("must be at least 3 characters") }
    it "uses singular 'character' for 1" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Str, min_length: 1)
      error_on(s, {"v" => any("")}, "v").should eq("must be at least 1 character")
    end
  end

  describe "max_length" do
    schema = Alumna::Schema.new.field("v", Alumna::FieldType::Str, max_length: 5)

    it "passes when length == max" { errors_for(schema, {"v" => any("abcde")}).should be_empty }
    it "passes when length < max" { errors_for(schema, {"v" => any("ab")}).should be_empty }
    it "fails when length > max" { error_on(schema, {"v" => any("abcdef")}, "v").should eq("must be at most 5 characters") }
    it "uses singular 'character' for 1" do
      s = Alumna::Schema.new.field("v", Alumna::FieldType::Str, max_length: 1)
      error_on(s, {"v" => any("ab")}, "v").should eq("must be at most 1 character")
    end
  end

  # ── Format constraints ────────────────────────────────────────────────────────

  describe "Email format" do
    schema = Alumna::Schema.new.field("email", Alumna::FieldType::Str, format: Alumna::FieldFormat::Email)

    it "accepts a valid email" { errors_for(schema, {"email" => any("alice@example.com")}).should be_empty }
    it "rejects missing @" { error_on(schema, {"email" => any("notanemail")}, "email").should eq("must be a valid email address") }
  end

  describe "Url format" do
    schema = Alumna::Schema.new.field("url", Alumna::FieldType::Str, format: Alumna::FieldFormat::Url)

    it "accepts https URL" { errors_for(schema, {"url" => any("https://example.com/path?q=1")}).should be_empty }
    it "rejects plain domain" { error_on(schema, {"url" => any("example.com")}, "url").should eq("must be a valid URL (http or https)") }
  end

  describe "Uuid format" do
    schema = Alumna::Schema.new.field("id", Alumna::FieldType::Str, format: Alumna::FieldFormat::Uuid)

    it "accepts a lowercase UUID" { errors_for(schema, {"id" => any("550e8400-e29b-41d4-a716-446655440000")}).should be_empty }
    it "rejects missing hyphens" { error_on(schema, {"id" => any("550e8400e29b41d4a716446655440000")}, "id").should eq("must be a valid UUID") }
  end

  # ── Constraint skipping on type error ────────────────────────────────────────

  describe "skipping length/format checks when type is wrong" do
    schema = Alumna::Schema.new.field("email", Alumna::FieldType::Str,
      min_length: 5,
      format: Alumna::FieldFormat::Email
    )

    it "reports only the type error" do
      errs = errors_for(schema, {"email" => any(123_i64)})
      errs.size.should eq(1)
      errs.first.message.should eq("must be a string")
    end
  end

  describe "edge cases" do
    it "requires a Nullable field when missing, but accepts null" do
      schema = Alumna::Schema.new.field("v", Alumna::FieldType::Nullable, required: true)
      error_fields(schema, empty_data).should contain("v")
      errors_for(schema, {"v" => any_nil}).should be_empty
    end

    it "Int rejects float values" do
      schema = Alumna::Schema.new.field("v", Alumna::FieldType::Int)
      error_on(schema, {"v" => any(2.5)}, "v").should eq("must be an integer")
    end

    it "Float rejects bool" do
      schema = Alumna::Schema.new.field("v", Alumna::FieldType::Float)
      error_on(schema, {"v" => any(true)}, "v").should eq("must be a number")
    end

    it "returns multiple errors for one field" do
      schema = Alumna::Schema.new.field("email", Alumna::FieldType::Str,
        min_length: 10,
        format: Alumna::FieldFormat::Email
      )
      # "a@b" is too short AND fails the email regex (no TLD)
      errs = errors_for(schema, {"email" => any("a@b")})
      errs.map(&.message).should contain("must be at least 10 characters")
      errs.map(&.message).should contain("must be a valid email address")
      errs.size.should eq(2)
    end

    it "ignores fields not defined in schema" do
      schema = Alumna::Schema.new.field("name", Alumna::FieldType::Str)
      errors_for(schema, {"name" => any("ok"), "extra" => any("ignored")}).should be_empty
    end

    it "accepts uppercase UUID" do
      schema = Alumna::Schema.new.field("id", Alumna::FieldType::Str, format: Alumna::FieldFormat::Uuid)
      errors_for(schema, {"id" => any("550E8400-E29B-41D4-A716-446655440000")}).should be_empty
    end

    it "rejects URL with trailing space" do
      schema = Alumna::Schema.new.field("u", Alumna::FieldType::Str, format: Alumna::FieldFormat::Url)
      error_on(schema, {"u" => any("https://example.com ")}, "u").should eq("must be a valid URL (http or https)")
    end

    it "required_on implies presence even when required: false" do
      schema = Alumna::Schema.new.str("title", required: false, required_on: [:create])
      errors_for(schema, empty_data, Alumna::ServiceMethod::Create).first.message.should eq("is required")
      errors_for(schema, empty_data, Alumna::ServiceMethod::Patch).should be_empty
    end
  end
end
