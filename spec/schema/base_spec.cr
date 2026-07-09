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
end
