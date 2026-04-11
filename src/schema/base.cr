module Alumna
  struct FieldDescriptor
    getter name : String
    getter type : FieldType
    getter required : Bool
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
    )
    end
  end

  enum FieldFormat
    Email
    Url
    Uuid
  end

  enum FieldType
    Str
    Int
    Float
    Bool
    Nullable # wraps another type — for v1, nullable fields declare this
  end

  class Schema
    getter fields : Array(FieldDescriptor)

    def initialize
      @fields = [] of FieldDescriptor
    end

    def field(
      name : String,
      type : FieldType,
      required : Bool = true,
      min_length : Int32? = nil,
      max_length : Int32? = nil,
      format : FieldFormat? = nil,
    ) : self
      @fields << FieldDescriptor.new(
        name: name,
        type: type,
        required: required,
        min_length: min_length,
        max_length: max_length,
        format: format
      )
      self
    end
  end
end
