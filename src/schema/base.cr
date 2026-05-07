module Alumna
  struct FieldDescriptor
    getter name : String
    getter type : FieldType
    getter required : Bool
    getter required_on : Array(ServiceMethod)?
    getter min_length : Int32?
    getter max_length : Int32?
    getter format_name : String?
    getter format_validator : Proc(String, Bool)?
    getter format_message : String?

    def initialize(
      @name : String,
      @type : FieldType,
      @required : Bool = true,
      @min_length : Int32? = nil,
      @max_length : Int32? = nil,
      @format_name : String? = nil,
      @format_validator : Proc(String, Bool)? = nil,
      @format_message : String? = nil,
      @required_on : Array(ServiceMethod)? = nil,
    )
    end
  end

  enum FieldType
    Str; Int; Float; Bool; Nullable
  end

  class Schema
    getter fields : Array(FieldDescriptor)

    def initialize
      @fields = [] of FieldDescriptor
    end

    # Core API - accepts Symbols for ergonomics
    def field(
      name : String,
      type : FieldType | Symbol,
      required : Bool = true,
      min_length : Int32? = nil,
      max_length : Int32? = nil,
      format : Symbol | String | Nil = nil,
      required_on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil,
    ) : self
      # normalize :str → FieldType::Str
      field_type = type.is_a?(Symbol) ? FieldType.parse(type.to_s.capitalize) : type

      # normalize format to downcased string, resolve validator once
      format_name = nil
      format_validator = nil
      format_message = nil

      if format
        format_name = case format
                      when Symbol then format.to_s.downcase
                      when String then format.downcase
                      end

        if format_name
          if entry = Formats.fetch(format_name)
            format_validator = entry.validator
            format_message = entry.message
          else
            raise ArgumentError.new("Unknown format: #{format_name}")
          end
        end
      end

      # normalize :create → [ServiceMethod::Create], also accepts single symbol
      norm_required_on = case required_on
                         in Nil
                           nil
                         in Array
                           required_on.map do |m|
                             m.is_a?(ServiceMethod) ? m : ServiceMethod.parse(m.to_s.capitalize)
                           end
                         in ServiceMethod
                           [required_on]
                         in Symbol
                           [ServiceMethod.parse(required_on.to_s.capitalize)]
                         end

      @fields << FieldDescriptor.new(
        name: name,
        type: field_type,
        required: required,
        min_length: min_length,
        max_length: max_length,
        format_name: format_name,
        format_validator: format_validator,
        format_message: format_message,
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
