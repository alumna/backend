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
    getter sub_schema : Schema?
    getter element_type : FieldType?

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
      @sub_schema : Schema? = nil,
      @element_type : FieldType? = nil,
    )
    end
  end

  enum FieldType
    Str; Int; Float; Bool; Nullable; Hash; Array
  end

  class Schema
    getter fields : Array(FieldDescriptor)

    def initialize
      @fields = [] of FieldDescriptor
    end

    def field(
      name : String,
      type : FieldType | Symbol,
      required : Bool = true,
      min_length : Int32? = nil,
      max_length : Int32? = nil,
      format : Symbol | String | Nil = nil,
      required_on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil,
      sub_schema : Schema? = nil,
      element_type : FieldType? = nil,
    ) : self
      field_type = type.is_a?(Symbol) ? FieldType.parse(type.to_s.capitalize) : type

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
        sub_schema: sub_schema,
        element_type: element_type
      )
      self
    end

    # --- Standard helpers ---
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

    # --- Nested helpers ---

    # For objects/hashes
    def hash(name : String, **opts, &block : Schema ->)
      sub = Schema.new
      yield sub
      field(name, :hash, **opts, sub_schema: sub)
    end

    # For arrays of primitives
    def array(name : String, of : FieldType | Symbol, **opts)
      el_type = of.is_a?(Symbol) ? FieldType.parse(of.to_s.capitalize) : of
      field(name, :array, **opts, element_type: el_type.as(FieldType))
    end

    # For arrays of objects
    def array(name : String, **opts, &block : Schema ->)
      sub = Schema.new
      yield sub
      field(name, :array, **opts, sub_schema: sub)
    end

    def self.build(& : self ->) : self
      schema = new
      yield schema
      schema
    end
  end
end
