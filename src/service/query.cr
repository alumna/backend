require "http"

module Alumna
  class Query
    enum Op
      Eq
      Ne
      Gt
      Gte
      Lt
      Lte
      In
      Nin
    end

    # 1. Raw condition holding unparsed URL strings
    struct Condition
      getter op : Op
      getter value : String | Array(String)

      def initialize(@op : Op, @value : String | Array(String))
      end
    end

    # 2. Coerced condition holding native Crystal types
    record TypedCondition, op : Op, value : AnyData

    getter filters : Hash(String, Array(Condition))
    getter limit : Int32?
    getter skip : Int32?
    getter sort : Array(Tuple(String, Int32))?
    getter select : Array(String)?

    def initialize(params : Http::ParamsView)
      @filters = Hash(String, Array(Condition)).new { |h, k| h[k] = [] of Condition }
      @limit = nil
      @skip = nil
      @sort = nil
      @select = nil

      params.each do |k, v|
        case k
        when "$limit"
          @limit = parse_positive_int(v)
        when "$skip"
          @skip = parse_positive_int(v)
        when "$sort"
          @sort = v.split(',').compact_map do |part|
            # Avoid split(':', 2) array allocation — use index directly.
            colon = part.index(':')
            field = colon ? part[0...colon] : part
            next if field.empty?
            dir_i = colon ? (part[colon + 1..].to_i? || 1) : 1
            {field, dir_i >= 0 ? 1 : -1}
          end
        when "$select"
          # Single compact_map pass instead of map + reject (one fewer array).
          @select = v.split(',').compact_map { |s| t = s.strip; t unless t.empty? }
        else
          next if k.starts_with?('$')

          field = k
          op_str = "$eq"

          if k.ends_with?(']') && (bracket_idx = k.index('['))
            field = k[0...bracket_idx]
            op_str = k[bracket_idx + 1...-1]
          end

          op = parse_op(op_str)
          if op.nil?
            field = k
            op = Op::Eq
          end

          if op.in? || op.nin?
            val = v.split(',')
            @filters[field] << Condition.new(op, val)
          else
            @filters[field] << Condition.new(op, v)
          end
        end
      end
    end

    def typed_filters(schema : Schema?) : Hash(String, Array(TypedCondition)) | ServiceError
      res = Hash(String, Array(TypedCondition)).new { |h, k| h[k] = [] of TypedCondition }

      @filters.each do |key, conds|
        fd = schema.try(&.find_field(key))
        type = fd.try(&.type) || FieldType::Str

        conds.each do |c|
          cv = c.value
          if c.op.in? || c.op.nin?
            raw_vals = cv.is_a?(Array(String)) ? cv : [cv]
            arr = [] of AnyData

            raw_vals.each do |v|
              cast_val = cast_value(v, type, fd)
              return ServiceError.bad_request("Invalid type for query parameter #{key}") if cast_val.nil? && !type.nullable?
              arr << cast_val
            end
            res[key] << TypedCondition.new(c.op, arr.as(AnyData))
          else
            raw_val = cv.is_a?(Array(String)) ? cv.first : cv
            cast_val = cast_value(raw_val, type, fd)

            return ServiceError.bad_request("Invalid type for query parameter #{key}") if cast_val.nil? && !type.nullable?
            res[key] << TypedCondition.new(c.op, cast_val)
          end
        end
      end
      res
    end

    private def cast_value(val : String, type : FieldType, fd : FieldDescriptor?) : AnyData
      effective_type = type
      if type.array? && fd
        if el_type = fd.element_type
          effective_type = el_type
        elsif fd.sub_schema
          effective_type = FieldType::Hash
        end
      end

      case effective_type
      when .int?   then val.to_i64?
      when .float? then val.to_f64?
      when .bool?  then val == "true" ? true : (val == "false" ? false : nil)
      when .time?
        # Time::Format::RFC_3339 has no parse? — rescue is the only option.
        Time::Format::RFC_3339.parse(val) rescue nil
      else val
      end
    end

    def empty? : Bool
      @filters.empty? && @limit.nil? && @skip.nil? && @sort.nil? && @select.nil?
    end

    @[AlwaysInline]
    private def parse_op(s : String) : Op?
      case s
      when "$eq"  then Op::Eq
      when "$ne"  then Op::Ne
      when "$gt"  then Op::Gt
      when "$gte" then Op::Gte
      when "$lt"  then Op::Lt
      when "$lte" then Op::Lte
      when "$in"  then Op::In
      when "$nin" then Op::Nin
      else             nil
      end
    end

    @[AlwaysInline]
    private def parse_positive_int(str : String) : Int32?
      return nil if str.empty?
      str.each_byte { |b| return nil unless 48 <= b <= 57 }
      str.to_i?
    end
  end
end
