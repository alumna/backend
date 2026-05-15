module Alumna
  struct FieldError
    getter field : String
    getter message : String

    def initialize(@field : String, @message : String)
    end
  end

  class Schema
    EMPTY_ERRORS = [] of FieldError

    def validate(data : Hash(String, AnyData), method : ServiceMethod? = nil) : Array(FieldError)
      errors = nil
      # A single tracker instantiated once per validation to trace paths without allocations
      path = [] of String | Int32
      errors = _validate(data, method, path, errors)
      errors || EMPTY_ERRORS
    end

    protected def _validate(data : Hash(String, AnyData), method : ServiceMethod?, path : Array(String | Int32), errors : Array(FieldError)?) : Array(FieldError)?
      @fields.each do |field|
        path.push(field.name)
        has_key = data.has_key?(field.name)
        value = data[field.name]?

        # --- Presence check ---
        unless has_key
          errors = push_error(errors, path, "is required") if required?(field, method)
          path.pop
          next
        end

        # --- Explicit null ---
        if value.nil?
          unless field.type.nullable?
            errors = push_error(errors, path, "is required") if required?(field, method)
          end
          path.pop
          next
        end

        # --- Type check ---
        if type_error = check_type(field.type, value)
          errors = push_error(errors, path, type_error)
          path.pop
          next
        end

        # --- Length Constraints (Shared for String & Array) ---
        if (field.type.str? && value.is_a?(String)) || (field.type.array? && value.is_a?(Array(AnyData)))
          if min = field.min_length
            if value.size < min
              msg = field.type.array? ? "must contain at least #{min} item#{min == 1 ? "" : "s"}" : "must be at least #{min} character#{min == 1 ? "" : "s"}"
              errors = push_error(errors, path, msg)
            end
          end
          if max = field.max_length
            if value.size > max
              msg = field.type.array? ? "must contain at most #{max} item#{max == 1 ? "" : "s"}" : "must be at most #{max} character#{max == 1 ? "" : "s"}"
              errors = push_error(errors, path, msg)
            end
          end
        end

        # --- String-only Formats ---
        if field.type.str? && value.is_a?(String)
          if validator = field.format_validator
            unless validator.call(value)
              errors = push_error(errors, path, field.format_message || "has an invalid format")
            end
          end
        end

        # --- Nested Traversal ---
        if field.type.hash? && value.is_a?(Hash(String, AnyData))
          if sub = field.sub_schema
            errors = sub._validate(value, method, path, errors)
          end
        elsif field.type.array? && value.is_a?(Array(AnyData))
          value.each_with_index do |item, idx|
            path.push(idx)
            if sub = field.sub_schema
              if item.is_a?(Hash(String, AnyData))
                errors = sub._validate(item, method, path, errors)
              else
                errors = push_error(errors, path, "must be an object")
              end
            elsif el_type = field.element_type
              if type_err = check_type(el_type, item)
                errors = push_error(errors, path, type_err)
              end
            end
            path.pop
          end
        end

        path.pop
      end

      errors
    end

    private def required?(field : FieldDescriptor, method : ServiceMethod?) : Bool
      if req_on = field.required_on
        method.nil? || req_on.includes?(method)
      else
        field.required
      end
    end

    @[AlwaysInline]
    private def push_error(errors : Array(FieldError)?, path : Array(String | Int32), message : String) : Array(FieldError)
      arr = errors || [] of FieldError

      # Generates a string like "user.address.coordinates[0]" natively
      field_path = String.build do |io|
        path.each_with_index do |part, i|
          if part.is_a?(Int32)
            io << "[" << part << "]"
          else
            io << "." if i > 0
            io << part
          end
        end
      end

      arr << FieldError.new(field_path, message)
      arr
    end

    private def check_type(type : FieldType, value : AnyData) : String?
      case type
      when .str?   then value.is_a?(String) ? nil : "must be a string"
      when .int?   then value.is_a?(Int64) ? nil : "must be an integer"
      when .float? then (value.is_a?(Float64) || value.is_a?(Int64)) ? nil : "must be a number"
      when .bool?  then value.is_a?(Bool) ? nil : "must be true or false"
      when .hash?  then value.is_a?(Hash(String, AnyData)) ? nil : "must be an object"
      when .array? then value.is_a?(Array(AnyData)) ? nil : "must be an array"
      else              nil
      end
    end
  end
end
