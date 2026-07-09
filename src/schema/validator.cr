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
      path = [] of String | Int32
      errors = _validate(data, method, path, errors)
      errors || EMPTY_ERRORS
    end

    protected def _validate(data : Hash(String, AnyData), method : ServiceMethod?, path : Array(String | Int32), errors : Array(FieldError)?) : Array(FieldError)?
      is_create = method.try(&.create?) || false
      is_write = method.try(&.write?) || false

      if @strict
        data.each_key do |key|
          unless @fields_by_name.has_key?(key)
            path.push(key)
            errors = push_error(errors, path, "is not allowed")
            path.pop
          end
        end
      end

      @fields.each do |field|
        path.push(field.name)

        begin
          has_key = data.has_key?(field.name)

          # --- Inject Defaults & Avoid Double Lookup ---
          value = if !has_key && field.has_default && is_create
                    v = field.default_value
                    data[field.name] = v
                    has_key = true
                    v
                  else
                    data[field.name]?
                  end

          # --- Read-Only Check ---
          if field.read_only && is_write && has_key
            errors = push_error(errors, path, "is read-only")
            next
          end

          # --- Presence check ---
          unless has_key
            errors = push_error(errors, path, "is required") if required?(field, method, is_write)
            next
          end

          # --- Explicit null check ---
          if value.nil?
            unless field.nullable
              errors = push_error(errors, path, "cannot be null")
            end
            next
          end

          # --- Type check ---
          if type_error = check_type(field.type, value)
            errors = push_error(errors, path, type_error)
            next
          end

          # --- Type-specific checks ---
          case value
          when String
            if field.type.str?
              if min = field.min_length
                errors = push_error(errors, path, "must be at least #{min} character#{min == 1 ? "" : "s"}") if value.size < min
              end
              if max = field.max_length
                errors = push_error(errors, path, "must be at most #{max} character#{max == 1 ? "" : "s"}") if value.size > max
              end
              if validator = field.format_validator
                errors = push_error(errors, path, field.format_message || "has an invalid format") unless validator.call(value)
              end
            end
          when Array(AnyData)
            if field.type.array?
              if min = field.min_length
                errors = push_error(errors, path, "must contain at least #{min} item#{min == 1 ? "" : "s"}") if value.size < min
              end
              if max = field.max_length
                errors = push_error(errors, path, "must contain at most #{max} item#{max == 1 ? "" : "s"}") if value.size > max
              end
              value.each_with_index do |item, idx|
                path.push(idx)
                begin
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
                ensure
                  path.pop
                end
              end
            end
          when Hash(String, AnyData)
            if field.type.hash?
              if sub = field.sub_schema
                errors = sub._validate(value, method, path, errors)
              end
            end
          end
        ensure
          path.pop
        end
      end

      errors
    end

    @[AlwaysInline]
    private def required?(field : FieldDescriptor, method : ServiceMethod?, is_write : Bool) : Bool
      return false if field.read_only && is_write

      if req_on = field.required_on
        method.nil? || req_on.includes?(method)
      else
        field.required
      end
    end

    @[AlwaysInline]
    private def push_error(errors : Array(FieldError)?, path : Array(String | Int32), message : String) : Array(FieldError)
      arr = errors || [] of FieldError

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

    @[AlwaysInline]
    private def check_type(type : FieldType, value : AnyData) : String?
      case type
      when .str?   then value.is_a?(String) ? nil : "must be a string"
      when .int?   then value.is_a?(Int64) ? nil : "must be an integer"
      when .float? then (value.is_a?(Float64) || value.is_a?(Int64)) ? nil : "must be a number"
      when .bool?  then value.is_a?(Bool) ? nil : "must be true or false"
      when .time?  then value.is_a?(Time) ? nil : "must be a time"
      when .bytes? then value.is_a?(Bytes) ? nil : "must be bytes"
      when .hash?  then value.is_a?(Hash(String, AnyData)) ? nil : "must be an object"
      when .array? then value.is_a?(Array(AnyData)) ? nil : "must be an array"
      when .any?   then nil
      else              nil
      end
    end
  end
end
