module Alumna
  struct FieldDescriptor
    getter name : String
    getter type : FieldType
    getter required : Bool
    getter required_on : Array(ServiceMethod)?
    getter min_length : Int32?
    getter max_length : Int32?
    getter format : FieldFormat?

    def initialize(
      @name : String,
      @type : FieldType,
      @required : Bool = true,
      @min_length : Int32? = nil,
      @max_length : Int32? = nil,
      @format : FieldFormat? = nil,
      @required_on : Array(ServiceMethod)? = nil,
    )
    end
  end

  enum FieldFormat
    Email; Url; Uuid
  end

  enum FieldType
    Str; Int; Float; Bool; Nullable
  end

  class Schema
    getter fields : Array(FieldDescriptor)

    def initialize
      @fields = [] of FieldDescriptor
    end

    # Core API — accepts Symbols for ergonomics
    def field(
      name : String,
      type : FieldType | Symbol,
      required : Bool = true,
      min_length : Int32? = nil,
      max_length : Int32? = nil,
      format : FieldFormat | Symbol | Nil = nil,
      required_on : Array(ServiceMethod | Symbol) | Nil = nil,
    ) : self
      # normalize :str → FieldType::Str
      field_type = type.is_a?(Symbol) ? FieldType.parse(type.to_s.capitalize) : type

      # normalize :email → FieldFormat::Email   ← NEW
      norm_format = format.is_a?(Symbol) ? FieldFormat.parse(format.to_s.capitalize) : format

      # normalize :create → ServiceMethod::Create
      norm_required_on = required_on.try &.map do |m|
        m.is_a?(ServiceMethod) ? m : ServiceMethod.parse(m.to_s.capitalize)
      end

      @fields << FieldDescriptor.new(
        name: name,
        type: field_type,
        required: required,
        min_length: min_length,
        max_length: max_length,
        format: norm_format,
        required_on: norm_required_on,
      )
      self
    end

    # --- tiny helpers for readability ---
    def str(name, **opts)
      field(name, :str, **opts)
    end

    def int(name, **opts)
      field(name, :int, **opts)
    end

    def float(name, **opts)
      field(name, :float, **opts)
    end

    def bool(name, **opts)
      field(name, :bool, **opts)
    end

    def nullable(name, **opts)
      field(name, :nullable, **opts)
    end

    # optional block-style builder
    def self.build(& : self ->) : self
      schema = new
      yield schema
      schema
    end
  end
end
