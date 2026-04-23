module Alumna
  struct FieldError
    getter field : String
    getter message : String

    def initialize(@field : String, @message : String)
    end
  end

  class Schema
    def validate(data : Hash(String, AnyData), method : ServiceMethod? = nil) : Array(FieldError)
      errors = [] of FieldError

      @fields.each do |field|
        has_key = data.has_key?(field.name)
        value = data[field.name]?

        # --- Presence check ---
        unless has_key
          req_on = field.required_on
          should_require = req_on ? (method.nil? || req_on.includes?(method)) : field.required
          errors << FieldError.new(field.name, "is required") if should_require
          next
        end

        # --- Explicit null ---
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
          next
        end

        # --- Constraint checks (only for strings) ---
        if field.type.str? && value.is_a?(String)
          str = value
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
          if validator = field.format_validator
            unless validator.call(str)
              errors << FieldError.new(field.name, field.format_message || "has an invalid format")
            end
          end
        end
      end

      errors
    end

    private def check_type(field : FieldDescriptor, value : AnyData) : String?
      case field.type
      when .str?
        value.is_a?(String) ? nil : "must be a string"
      when .int? then value.is_a?(Int64) ? nil : "must be an integer"
      when .float?
        (value.is_a?(Float64) || value.is_a?(Int64)) ? nil : "must be a number"
      when .bool?
        value.is_a?(Bool) ? nil : "must be true or false"
      else
        nil
      end
    end
  end
end
