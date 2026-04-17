module Alumna
  struct FieldError
    getter field : String
    getter message : String

    def initialize(@field : String, @message : String)
    end
  end

  class Schema
    EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
    URL_REGEX   = /\Ahttps?:\/\/[^\s]+\z/
    UUID_REGEX  = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    def validate(data : Hash(String, AnyData)) : Array(FieldError)
      errors = [] of FieldError

      @fields.each do |field|
        value = data[field.name]?

        # --- Presence check ---
        if value.nil? || value.raw.nil?
          if field.required
            errors << FieldError.new(field.name, "is required")
          end
          # Nothing more to validate for a missing optional field
          next
        end

        # --- Type check ---
        type_error = check_type(field, value)
        if type_error
          errors << FieldError.new(field.name, type_error)
          # Skip constraint checks when the type is already wrong —
          # length/format errors on a mis-typed value are misleading
          next
        end

        # --- Constraint checks (only meaningful for strings) ---
        if field.type.str?
          str = value.as_s

          if min = field.min_length
            if str.size < min
              errors << FieldError.new(field.name, "must be at least #{min} character#{min == 1 ? "" : "s"}")
            end
          end

          if max = field.max_length
            if str.size > max
              errors << FieldError.new(field.name, "must be at most #{max} character#{max == 1 ? "" : "s"}")
            end
          end

          if fmt = field.format
            unless valid_format?(str, fmt)
              errors << FieldError.new(field.name, format_message(fmt))
            end
          end
        end
      end

      errors
    end

    private def check_type(field : FieldDescriptor, value : AnyData) : String?
      case field.type
      when .str?
        value.as_s? ? nil : "must be a string"
      when .int?
        # JSON integers arrive as Int64 inside AnyData
        value.as_i64? || value.as_i? ? nil : "must be an integer"
      when .float?
        value.as_f? || value.as_i? ? nil : "must be a number"
      when .bool?
        !value.as_bool?.nil? ? nil : "must be true or false"
      else
        nil
      end
    end

    private def valid_format?(value : String, format : FieldFormat) : Bool
      case format
      when .email?
        # Intentionally simple: local@domain.tld — not RFC 5322 complete,
        # which is the right pragmatic choice for a framework validator
        !!(value =~ EMAIL_REGEX)
      when .url?
        !!(value =~ URL_REGEX)
      when .uuid?
        !!(value =~ UUID_REGEX)
      else
        true
      end
    end

    private def format_message(format : FieldFormat) : String
      case format
      when .email? then "must be a valid email address"
      when .url?   then "must be a valid URL (http or https)"
      when .uuid?  then "must be a valid UUID"
      else              "has an invalid format"
      end
    end
  end
end
