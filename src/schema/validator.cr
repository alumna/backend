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

    def validate(data : Hash(String, AnyData), method : ServiceMethod? = nil) : Array(FieldError)
      errors = [] of FieldError

      @fields.each do |field|
        has_key = data.has_key?(field.name)
        value = data[field.name]? # nil if missing OR explicit null

        # --- Presence check (key not sent at all) ---
        unless has_key
          req_on = field.required_on
          should_require = req_on ? (method.nil? || req_on.includes?(method)) : field.required
          errors << FieldError.new(field.name, "is required") if should_require
          next
        end

        # --- Explicit null (key sent with null value) ---
        if value.nil?
          next if field.type.nullable?

          req_on = field.required_on
          should_require = req_on ? (method.nil? || req_on.includes?(method)) : field.required
          errors << FieldError.new(field.name, "is required") if should_require
          next
        end

        # --- Type check ---
        if type_error = check_type(field, value)
          errors << FieldError.new(field.name, type_error)
          next # skip length/format when type is wrong
        end

        # --- Constraint checks (strings only) ---
        if field.type.str?
          str = value.raw.as(String)

          if min = field.min_length
            errors << FieldError.new(field.name, "must be at least #{min} character#{min == 1 ? "" : "s"}") if str.size < min
          end

          if max = field.max_length
            errors << FieldError.new(field.name, "must be at most #{max} character#{max == 1 ? "" : "s"}") if str.size > max
          end

          if fmt = field.format
            errors << FieldError.new(field.name, format_message(fmt)) unless valid_format?(str, fmt)
          end
        end
      end

      errors
    end

    private def check_type(field, value : AnyData) : String?
      case field.type
      when .str?   then value.raw.is_a?(String) ? nil : "must be a string"
      when .int?   then value.raw.is_a?(Int) ? nil : "must be an integer"
      when .float? then (value.raw.is_a?(Float) || value.raw.is_a?(Int)) ? nil : "must be a number"
      when .bool?  then value.raw.is_a?(Bool) ? nil : "must be true or false"
      else              nil
      end
    end

    private def valid_format?(value : String, format : FieldFormat) : Bool
      case format
      when .email? then !!(value =~ EMAIL_REGEX)
      when .url?   then !!(value =~ URL_REGEX)
      when .uuid?  then !!(value =~ UUID_REGEX)
      else              true
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
