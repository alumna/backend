module Alumna
  struct FieldError
    getter field : String
    getter message : String

    def initialize(@field : String, @message : String)
    end
  end

  class Schema
    # Shared sentinel returned when validation passes.
    # Treat as read-only - never mutate the result of validate directly.
    EMPTY_ERRORS = [] of FieldError

    def validate(data : Hash(String, AnyData), method : ServiceMethod? = nil) : Array(FieldError)
      errors = nil

      @fields.each do |field|
        has_key = data.has_key?(field.name)
        value = data[field.name]?

        # --- Presence check ---
        unless has_key
          errors = push_error(errors, field.name, "is required") if required?(field, method)
          next
        end

        # --- Explicit null ---
        if value.nil?
          next if field.type.nullable?
          errors = push_error(errors, field.name, "is required") if required?(field, method)
          next
        end

        # --- Type check ---
        if type_error = check_type(field, value)
          errors = push_error(errors, field.name, type_error)
          next
        end

        # --- Constraint checks (only for strings) ---
        if field.type.str? && value.is_a?(String)
          str = value
          if min = field.min_length
            if str.size < min
              errors = push_error(errors, field.name, "must be at least #{min} character#{min == 1 ? "" : "s"}")
            end
          end
          if max = field.max_length
            if str.size > max
              errors = push_error(errors, field.name, "must be at most #{max} character#{max == 1 ? "" : "s"}")
            end
          end
          if validator = field.format_validator
            unless validator.call(str)
              errors = push_error(errors, field.name, field.format_message || "has an invalid format")
            end
          end
        end
      end

      errors || EMPTY_ERRORS
    end

    # Returns true if the field is required for the given method context.
    # Extracted to eliminate the identical logic that appeared in both the
    # presence check and the explicit-null check.
    private def required?(field : FieldDescriptor, method : ServiceMethod?) : Bool
      if req_on = field.required_on
        method.nil? || req_on.includes?(method)
      else
        field.required
      end
    end

    # Lazily allocates the errors array on the first error, then reuses it.
    # Returns the (possibly newly created) array with the new entry appended.
    @[AlwaysInline]
    private def push_error(errors : Array(FieldError)?, field : String, message : String) : Array(FieldError)
      arr = errors || [] of FieldError
      arr << FieldError.new(field, message)
      arr
    end

    private def check_type(field : FieldDescriptor, value : AnyData) : String?
      case field.type
      when .str?   then value.is_a?(String) ? nil : "must be a string"
      when .int?   then value.is_a?(Int64) ? nil : "must be an integer"
      when .float? then (value.is_a?(Float64) || value.is_a?(Int64)) ? nil : "must be a number"
      when .bool?  then value.is_a?(Bool) ? nil : "must be true or false"
      else              nil
      end
    end
  end
end
