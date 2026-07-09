module Alumna
  # Sentinel struct to distinguish omitted arguments from explicit nils
  struct Unprovided; end

  class FieldDescriptor
    getter name : String
    getter type : FieldType
    getter required : Bool
    getter nullable : Bool
    getter unique : Bool
    getter indexed : Bool
    getter read_only : Bool
    getter required_on : Array(ServiceMethod)?
    getter min_length : Int32?
    getter max_length : Int32?
    getter format_name : String?
    getter format_validator : Proc(String, Bool)?
    getter format_message : String?
    getter sub_schema : Schema?
    getter element_type : FieldType?

    getter has_default : Bool
    @default_value : AnyData | Proc(AnyData) | Nil

    def initialize(
      @name : String,
      @type : FieldType,
      @required : Bool = true,
      @nullable : Bool = false,
      @unique : Bool = false,
      @indexed : Bool = false,
      @read_only : Bool = false,
      @min_length : Int32? = nil,
      @max_length : Int32? = nil,
      @format_name : String? = nil,
      @format_validator : Proc(String, Bool)? = nil,
      @format_message : String? = nil,
      @required_on : Array(ServiceMethod)? = nil,
      @sub_schema : Schema? = nil,
      @element_type : FieldType? = nil,
      default : AnyData | Proc(AnyData) | Unprovided | Nil = Unprovided.new,
    )
      @has_default = !default.is_a?(Unprovided)
      @default_value = default.is_a?(Unprovided) ? nil : default.as(AnyData | Proc(AnyData) | Nil)
    end

    def default_value : AnyData
      val = @default_value
      val.is_a?(Proc(AnyData)) ? val.call : val
    end
  end

  # Nullable is replaced by Any. Nullability is now a trait on all fields.
  enum FieldType
    Str; Int; Float; Bool; Time; Bytes; Any; Hash; Array
  end

  record IndexDef, fields : Array(String), unique : Bool

  class Schema
    getter fields : Array(FieldDescriptor)
    getter strict : Bool
    getter schema_indexes : Array(IndexDef)

    protected getter fields_by_name : Hash(String, FieldDescriptor)

    def initialize(@strict : Bool = true)
      @fields = [] of FieldDescriptor
      @fields_by_name = {} of String => FieldDescriptor
      @schema_indexes = [] of IndexDef
    end

    private def resolve_field_type(type : FieldType | Symbol) : FieldType
      return type if type.is_a?(FieldType)
      case type
      when :str   then FieldType::Str
      when :int   then FieldType::Int
      when :float then FieldType::Float
      when :bool  then FieldType::Bool
      when :time  then FieldType::Time
      when :bytes then FieldType::Bytes
      when :any   then FieldType::Any
      when :hash  then FieldType::Hash
      when :array then FieldType::Array
      else             raise ArgumentError.new("Unknown enum Alumna::FieldType: #{type}")
      end
    end

    private def resolve_format(format : Symbol | String | Nil) : {name: String?, validator: Proc(String, Bool)?, message: String?}
      return {name: nil, validator: nil, message: nil} unless format

      format_name = case format
                    when Symbol then format.to_s.downcase
                    when String then format.downcase
                    else             nil
                    end

      return {name: nil, validator: nil, message: nil} unless format_name

      if entry = Formats.fetch(format_name)
        {name: format_name, validator: entry.validator, message: entry.message}
      else
        raise ArgumentError.new("Unknown format: #{format_name}")
      end
    end

    def index(fields : Array(String) | String, unique : Bool = false) : self
      arr = fields.is_a?(String) ? [fields] : fields
      @schema_indexes << IndexDef.new(arr, unique)
      self
    end

    def field(
      name : String,
      type : FieldType | Symbol,
      required : Bool = true,
      nullable : Bool = false,
      unique : Bool = false,
      indexed : Bool = false,
      read_only : Bool = false,
      min_length : Int32? = nil,
      max_length : Int32? = nil,
      format : Symbol | String | Nil = nil,
      required_on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil,
      sub_schema : Schema? = nil,
      element_type : FieldType? = nil,
      default : AnyData | Proc(AnyData) | Unprovided | Nil = Unprovided.new,
    ) : self
      field_type = resolve_field_type(type)
      fmt = resolve_format(format)

      norm_required_on = case required_on
                         in Nil
                           nil
                         in Array(ServiceMethod)
                           required_on
                         in Array
                           required_on.map { |m| m.is_a?(ServiceMethod) ? m : ServiceMethod.parse(m.to_s.capitalize) }
                         in ServiceMethod
                           [required_on]
                         in Symbol
                           [ServiceMethod.parse(required_on.to_s.capitalize)]
                         end

      fd = FieldDescriptor.new(
        name: name,
        type: field_type,
        required: required,
        nullable: nullable,
        unique: unique,
        indexed: indexed,
        read_only: read_only,
        min_length: min_length,
        max_length: max_length,
        format_name: fmt[:name],
        format_validator: fmt[:validator],
        format_message: fmt[:message],
        required_on: norm_required_on,
        sub_schema: sub_schema,
        element_type: element_type,
        default: default
      )

      @fields << fd
      @fields_by_name[name] = fd
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

    def time(name, **opts)
      field(name, :time, **opts)
    end

    def bytes(name, **opts)
      field(name, :bytes, **opts)
    end

    def any(name, **opts)
      field(name, :any, **opts)
    end

    # --- Nested helpers ---

    # For objects/hashes
    def hash(name : String, **opts, &block : Schema ->)
      sub = Schema.new(strict: @strict)
      yield sub
      field(name, :hash, **opts, sub_schema: sub)
    end

    # For arrays of primitives
    def array(name : String, of : FieldType | Symbol, **opts)
      el_type = resolve_field_type(of)
      field(name, :array, **opts, element_type: el_type)
    end

    # For arrays of objects
    def array(name : String, **opts, &block : Schema ->)
      sub = Schema.new(strict: @strict)
      yield sub
      field(name, :array, **opts, sub_schema: sub)
    end

    def find_field(path : String) : FieldDescriptor?
      parts = path.split('.')
      current_schema = self
      field = nil

      parts.each_with_index do |part, i|
        # Ignore array indices in query params (e.g. users[0].age -> users.age)
        clean_part = part.sub(/\[\d+\]/, "")

        field = current_schema.fields_by_name[clean_part]?
        return nil unless field

        if i < parts.size - 1
          if sub = field.sub_schema
            current_schema = sub
          else
            return nil
          end
        end
      end
      field
    end

    def self.build(strict : Bool = true, & : self ->) : self
      schema = new(strict: strict)
      yield schema
      schema
    end
  end
end
