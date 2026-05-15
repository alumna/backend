module Alumna
  class MemoryAdapter < Service
    @store : Hash(String, Hash(String, AnyData))
    @next_id : Int64
    @mutex : Sync::Mutex

    def initialize(schema : Schema? = nil)
      super(schema)
      @store = {} of String => Hash(String, AnyData)
      @next_id = 1_i64
      @mutex = Sync::Mutex.new
    end

    private def compare_values(a : AnyData, b : AnyData) : Int32
      return 0 if a.nil? && b.nil?
      return -1 if a.nil?
      return 1 if b.nil?

      if (a.is_a?(Int64) || a.is_a?(Float64)) && (b.is_a?(Int64) || b.is_a?(Float64))
        return (a.as(Int64 | Float64) <=> b.as(Int64 | Float64)) || 0
      end

      if a.class == b.class
        case a
        when String
          return a <=> b.as(String)
        when Bool
          return (a ? 1 : 0) <=> (b.as(Bool) ? 1 : 0)
        end
      end

      a.to_s <=> b.to_s
    end

    private def extract_value(rec : Hash(String, AnyData), field : String) : AnyData
      # Fast path for standard top-level fields
      return rec[field] if rec.has_key?(field)

      # Fallback to dot notation for nested fields
      current : AnyData = rec
      field.split('.').each do |part|
        if current.is_a?(Hash(String, AnyData))
          if current.has_key?(part)
            current = current[part]
          else
            return nil
          end
        else
          return nil
        end
      end
      current
    end

    private def match_condition?(val : AnyData, cond : Query::Condition) : Bool
      # Distributor arrays natively. e.g. `$ne` requires ALL elements to not match.
      if val.is_a?(Array(AnyData))
        if cond.op.ne? || cond.op.nin?
          val.all? { |v| match_single_value?(v, cond) }
        else
          val.any? { |v| match_single_value?(v, cond) }
        end
      else
        match_single_value?(val, cond)
      end
    end

    private def match_single_value?(val : AnyData, cond : Query::Condition) : Bool
      str_val = val.try(&.to_s)

      case cond.op
      when .eq?
        str_val == cond.value
      when .ne?
        str_val != cond.value
      when .in?
        cv = cond.value
        cv.is_a?(Array) ? cv.includes?(str_val) : false
      when .nin?
        cv = cond.value
        cv.is_a?(Array) ? !cv.includes?(str_val) : true
      else
        cv = cond.value
        return false unless cv.is_a?(String)

        cmp = compare_query_value(val, cv)
        return false unless cmp

        case cond.op
        when .gt?  then cmp > 0
        when .gte? then cmp >= 0
        when .lt?  then cmp < 0
        when .lte? then cmp <= 0
        else            false
        end
      end
    end

    private def compare_query_value(record_val : AnyData, query_val : String) : Int32?
      return nil if record_val.nil?

      case record_val
      when Int64
        if q_int = query_val.to_i64?
          record_val <=> q_int
        else
          nil
        end
      when Float64
        if q_float = query_val.to_f64?
          record_val <=> q_float
        else
          nil
        end
      when Bool
        q_bool = query_val == "true" ? true : (query_val == "false" ? false : nil)
        return nil if q_bool.nil?
        (record_val ? 1 : 0) <=> (q_bool ? 1 : 0)
      when String
        record_val <=> query_val
      else
        nil
      end
    end

    def find(ctx : RuleContext) : Array(Hash(String, AnyData))
      @mutex.synchronize do
        q = ctx.query
        records = @store.values

        # 1) filters
        unless q.filters.empty?
          records = records.select do |rec|
            q.filters.all? do |field, conditions|
              val = extract_value(rec, field)
              conditions.all? do |cond|
                match_condition?(val, cond)
              end
            end
          end
        end

        # 2) sort
        if sort = q.sort
          records.sort! do |a, b|
            sort.reduce(0) do |cmp, (field, dir)|
              next cmp if cmp != 0
              compare_values(extract_value(a, field), extract_value(b, field)) * dir
            end
          end
        end

        # 3) skip + limit
        records = records.skip(q.skip || 0)
        if limit = q.limit
          records = records.first(limit)
        end

        # 4) select
        if fields = q.select
          # LCOV_EXCL_START - kcov wrongly misses.map
          records.map do |rec|
            # LCOV_EXCL_STOP
            selected = rec.select(fields)
            selected["id"] = rec["id"] if rec["id"]? && !selected.has_key?("id")
            selected
          end
        else
          records
        end
      end
    end

    def get(ctx : RuleContext) : Hash(String, AnyData)?
      @mutex.synchronize do
        id = ctx.id
        return nil if id.nil?
        @store[id]?
      end
    end

    def create(ctx : RuleContext) : Hash(String, AnyData)
      @mutex.synchronize do
        id = @next_id.to_s
        @next_id += 1
        record = ctx.data.dup
        record["id"] = id
        @store[id] = record
        record
      end
    end

    def update(ctx : RuleContext) : Hash(String, AnyData)
      @mutex.synchronize do
        id = ctx.id || raise ServiceError.bad_request("ID required for update")
        raise ServiceError.not_found unless @store.has_key?(id)
        record = ctx.data.dup
        record["id"] = id
        @store[id] = record
        record
      end
    end

    def patch(ctx : RuleContext) : Hash(String, AnyData)
      @mutex.synchronize do
        id = ctx.id || raise ServiceError.bad_request("ID required for patch")
        existing = @store[id]? || raise ServiceError.not_found
        record = existing.merge(ctx.data)
        record["id"] = id
        @store[id] = record
        record
      end
    end

    def remove(ctx : RuleContext) : Bool
      @mutex.synchronize do
        id = ctx.id || raise ServiceError.bad_request("ID required for remove")
        !@store.delete(id).nil?
      end
    end
  end
end
