require "../spec_helper"

describe Alumna::Schema do
  describe "initialization" do
    it "starts empty and strict by default" do
      s = Alumna::Schema.new
      s.fields.should be_empty
      s.strict.should be_true
      s.schema_indexes.should be_empty
    end

    it "accepts strict: false" do
      s = Alumna::Schema.new(strict: false)
      s.strict.should be_false
    end
  end

  describe "#field" do
    it "normalizes :str symbol" do
      fd = Alumna::Schema.new.field("name", :str).fields.first
      fd.name.should eq("name")
      fd.type.should eq(Alumna::FieldType::Str)
    end

    it "accepts FieldType enum" do
      fd = Alumna::Schema.new.field("age", Alumna::FieldType::Int).fields.first
      fd.type.should eq(Alumna::FieldType::Int)
    end

    it "defaults required to true" do
      Alumna::Schema.new.field("a", :bool).fields.first.required.should be_true
    end

    it "stores lengths" do
      fd = Alumna::Schema.new.field("t", :str, min_length: 2, max_length: 10).fields.first
      fd.min_length.should eq(2)
      fd.max_length.should eq(10)
    end

    it "stores traits (read_only, nullable, unique, indexed)" do
      fd = Alumna::Schema.new.field("x", :str, read_only: true, nullable: true, unique: true, indexed: true).fields.first
      fd.read_only.should be_true
      fd.nullable.should be_true
      fd.unique.should be_true
      fd.indexed.should be_true
    end
  end

  describe "default values" do
    it "identifies when a default is not provided" do
      fd = Alumna::Schema.new.field("x", :str).fields.first
      fd.has_default.should be_false
      fd.default_value.should be_nil
    end

    it "identifies when a default is explicitly provided as nil" do
      fd = Alumna::Schema.new.field("x", :str, default: nil).fields.first
      fd.has_default.should be_true
      fd.default_value.should be_nil
    end

    it "stores and returns static default values" do
      fd = Alumna::Schema.new.field("x", :int, default: 42_i64).fields.first
      fd.has_default.should be_true
      fd.default_value.should eq(42_i64)
    end

    it "stores and evaluates dynamic default Procs at runtime" do
      fd = Alumna::Schema.new.field("x", :str, default: -> { "dynamic".as(Alumna::AnyData) }).fields.first
      fd.has_default.should be_true
      fd.default_value.should eq("dynamic")
    end
  end

  describe "schema-level indexes" do
    it "stores single field indexes" do
      s = Alumna::Schema.new.index("email", unique: true)
      idx = s.schema_indexes.first
      idx.fields.should eq(["email"])
      idx.unique.should be_true
    end

    it "stores compound field indexes" do
      s = Alumna::Schema.new.index(["user_id", "status"])
      idx = s.schema_indexes.first
      idx.fields.should eq(["user_id", "status"])
      idx.unique.should be_false
    end
  end

  describe "format" do
    it "accepts :email, :url, :uuid" do
      s = Alumna::Schema.new.str("e", format: :email)
      fd = s.fields.first
      fd.format_name.should eq("email")
      fd.format_validator.should_not be_nil
      fd.format_message.should eq("must be a valid email address")
    end

    it "normalizes strings and capitalized symbols" do
      s1 = Alumna::Schema.new.field("x", :str, format: :url)
      s1.fields.first.format_name.should eq("url")

      s2 = Alumna::Schema.new.str("y", format: "Uuid")
      s2.fields.first.format_name.should eq("uuid")
    end

    it "allows nil" do
      fd = Alumna::Schema.new.str("n").fields.first
      fd.format_name.should be_nil
      fd.format_validator.should be_nil
      fd.format_message.should be_nil
    end

    it "raises for unknown format" do
      expect_raises(ArgumentError, /Unknown format/) do
        Alumna::Schema.new.str("x", format: :not_a_format)
      end
    end
  end

  describe "required_on" do
    it "normalizes array of symbols" do
      fd = Alumna::Schema.new.str("t", required_on: [:create, :update]).fields.first
      fd.required_on.should eq([Alumna::ServiceMethod::Create, Alumna::ServiceMethod::Update])
    end

    it "normalizes single symbol" do
      fd = Alumna::Schema.new.str("t", required_on: :patch).fields.first
      fd.required_on.should eq([Alumna::ServiceMethod::Patch])
    end

    it "normalizes single enum" do
      fd = Alumna::Schema.new.str("t", required_on: Alumna::ServiceMethod::Create).fields.first
      fd.required_on.should eq([Alumna::ServiceMethod::Create])
    end

    it "normalizes mixed symbols and enums" do
      fd = Alumna::Schema.new.str("t",
        required_on: [Alumna::ServiceMethod::Patch, :remove]
      ).fields.first
      fd.required_on.should eq([Alumna::ServiceMethod::Patch, Alumna::ServiceMethod::Remove])
    end

    it "accepts nil" do
      Alumna::Schema.new.str("t").fields.first.required_on.should be_nil
    end

    it "raises for unknown method" do
      expect_raises(ArgumentError, /Unknown enum Alumna::ServiceMethod/) do
        Alumna::Schema.new.str("x", required_on: [:bogus])
      end
    end
  end

  describe "helpers" do
    it "set correct types and forward options" do
      s = Alumna::Schema.new
        .str("a")
        .int("b", required: false)
        .float("c")
        .bool("d")
        .any("e", nullable: true)
        .time("f")
        .bytes("g")

      s.fields.map(&.type).should eq([
        Alumna::FieldType::Str,
        Alumna::FieldType::Int,
        Alumna::FieldType::Float,
        Alumna::FieldType::Bool,
        Alumna::FieldType::Any,
        Alumna::FieldType::Time,
        Alumna::FieldType::Bytes,
      ])
      s.fields[1].required.should be_false
      s.fields[4].nullable.should be_true
    end
  end

  describe "chaining and builder" do
    it "returns self" do
      s = Alumna::Schema.new
      s.str("a").int("b").should be(s)
    end

    it "builds via block and preserves order" do
      s = Alumna::Schema.build do |sc|
        sc.str("first")
        sc.int("second")
      end
      s.fields.map(&.name).should eq(["first", "second"])
    end

    it "builds via block with strict flag" do
      s = Alumna::Schema.build(strict: false) do |sc|
        sc.str("first")
      end
      s.strict.should be_false
    end
  end

  describe "error paths for type" do
    it "raises for unknown type" do
      expect_raises(ArgumentError, /Unknown enum Alumna::FieldType/) do
        Alumna::Schema.new.field("x", :nope)
      end
    end
  end

  describe "validator integration" do
    it "validates format when given as symbol" do
      schema = Alumna::Schema.new.str("email", format: :email)
      errors = schema.validate({"email" => "not-an-email"} of String => Alumna::AnyData)
      errors.first.message.should eq("must be a valid email address")
    end
  end

  describe "recursive field collection (unique and indexed)" do
    it "collects unique and indexed fields recursively with correct dot-notation paths" do
      schema = Alumna::Schema.new
        .str("id", unique: true)
        .str("tenant_id", indexed: true)
        .str("name") # neither
        .hash("profile") do |p|
          p.str("handle", unique: true)
          p.str("category", indexed: true)
          p.hash("preferences") do |prefs|
            prefs.bool("marketing", indexed: true)
          end
        end
        .array("users") do |u|
          # These are inside an array, so the recursive walker MUST stop
          # and ignore them to prevent generating invalid dot-notation paths.
          u.str("email", unique: true)
          u.str("role", indexed: true)
        end

      # Check unique_fields
      uniq = schema.unique_fields
      uniq.size.should eq(2)
      uniq.map(&.first).should eq(["id", "profile.handle"])

      # Check indexed_fields (should include unique ones too!)
      idx = schema.indexed_fields
      idx.size.should eq(5)

      expected_indexed_paths = [
        "id",
        "tenant_id",
        "profile.handle",
        "profile.category",
        "profile.preferences.marketing",
      ]
      idx.map(&.first).should eq(expected_indexed_paths)
    end
  end
end
