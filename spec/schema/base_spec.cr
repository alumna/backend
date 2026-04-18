require "../spec_helper"
require "json"

describe Alumna::Schema do
  describe "initialization" do
    it "starts empty" do
      Alumna::Schema.new.fields.should be_empty
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
  end

  describe "format" do
    it "accepts :email, :url, :uuid" do
      s = Alumna::Schema.new.str("e", format: :email)
      s.fields.first.format.should eq(Alumna::FieldFormat::Email)
    end

    it "accepts enum directly and capitalized symbols" do
      s1 = Alumna::Schema.new.field("x", :str, format: Alumna::FieldFormat::Url)
      s1.fields.first.format.should eq(Alumna::FieldFormat::Url)

      s2 = Alumna::Schema.new.str("y", format: :Uuid)
      s2.fields.first.format.should eq(Alumna::FieldFormat::Uuid)
    end

    it "allows nil" do
      Alumna::Schema.new.str("n").fields.first.format.should be_nil
    end

    # FIXED: Crystal's message is "Unknown enum...", not "Invalid FieldFormat"
    it "raises for unknown format" do
      expect_raises(ArgumentError, /Unknown enum Alumna::FieldFormat/) do
        Alumna::Schema.new.str("x", format: :not_a_format)
      end
    end
  end

  describe "required_on" do
    it "normalizes array of symbols" do
      fd = Alumna::Schema.new.str("t", required_on: [:create, :update]).fields.first
      fd.required_on.should eq([Alumna::ServiceMethod::Create, Alumna::ServiceMethod::Update])
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
        .nullable("e", required_on: [:patch])

      s.fields.map(&.type).should eq([
        Alumna::FieldType::Str,
        Alumna::FieldType::Int,
        Alumna::FieldType::Float,
        Alumna::FieldType::Bool,
        Alumna::FieldType::Nullable,
      ])
      s.fields[1].required.should be_false
      s.fields[4].required_on.should eq([Alumna::ServiceMethod::Patch])
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
  end

  describe "error paths for type" do
    it "raises for unknown type" do
      expect_raises(ArgumentError, /Unknown enum Alumna::FieldType/) do
        Alumna::Schema.new.field("x", :nope)
      end
    end
  end

  describe "validator integration (kept from your original)" do
    it "validates format when given as symbol" do
      schema = Alumna::Schema.new.str("email", format: :email)
      errors = schema.validate({"email" => JSON::Any.new("not-an-email")})
      errors.first.message.should eq("must be a valid email address")
    end
  end
end
