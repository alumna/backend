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
        when Time
          return a <=> b.as(Time)
          # LCOV_EXCL_START - kcov wrongly missed the "when Bytes"
        when Bytes
          # LCOV_EXCL_STOP
          # Crystal's Slice(UInt8) implements <=>
          return a <=> b.as(Bytes)
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

    private def match_condition?(val : AnyData, cond : Query::TypedCondition) : Bool
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

    private def match_single_value?(val : AnyData, cond : Query::TypedCondition) : Bool
      case cond.op
      when .eq?
        compare_values(val, cond.value) == 0
      when .ne?
        compare_values(val, cond.value) != 0
      when .in?
        cv = cond.value
        cv.is_a?(Array) ? cv.any? { |v| compare_values(val, v) == 0 } : false
      when .nin?
        cv = cond.value
        cv.is_a?(Array) ? cv.none? { |v| compare_values(val, v) == 0 } : true
      else
        cmp = compare_values(val, cond.value)
        case cond.op
        when .gt?  then cmp > 0
        when .gte? then cmp >= 0
        when .lt?  then cmp < 0
        when .lte? then cmp <= 0
        else            false
        end
      end
    end

    def find(ctx : RuleContext) : Array(Hash(String, AnyData)) | ServiceError
      q = ctx.query
      filters = q.typed_filters(schema)
      return filters if filters.is_a?(ServiceError)

      # 1) Lock only for shallow extraction!
      records = @mutex.synchronize { @store.values }

      # 2) filters (no lock needed)
      unless filters.empty?
        records = records.select do |rec|
          filters.all? do |field, conditions|
            val = extract_value(rec, field)
            conditions.all? { |cond| match_condition?(val, cond) }
          end
        end
      end

      # 3) sort
      if sort = q.sort
        records.sort! do |a, b|
          sort.reduce(0) do |cmp, (field, dir)|
            next cmp if cmp != 0
            compare_values(extract_value(a, field), extract_value(b, field)) * dir
          end
        end
      end

      # 4) skip + limit
      records = records.skip(q.skip || 0)
      if limit = q.limit
        records = records.first(limit)
      end

      # 5) select
      if fields = q.select
        records.map do |rec|
          selected = rec.select(fields)
          selected["id"] = rec["id"] if rec["id"]? && !selected.has_key?("id")
          selected
        end
      else
        records
      end
    end

    def get(ctx : RuleContext) : Hash(String, AnyData)? | ServiceError
      id = ctx.id
      return nil unless id
      @mutex.synchronize { @store[id]? }
    end

    def create(ctx : RuleContext) : Hash(String, AnyData) | ServiceError
      record = ctx.data.dup
      @mutex.synchronize do
        id = @next_id.to_s
        @next_id += 1
        record["id"] = id
        @store[id] = record
      end
      record
    end

    def update(ctx : RuleContext) : Hash(String, AnyData) | ServiceError
      id = ctx.id
      return ServiceError.bad_request("ID required for update") unless id

      record = ctx.data.dup
      record["id"] = id

      @mutex.synchronize do
        return ServiceError.not_found unless @store.has_key?(id)
        @store[id] = record
      end
      record
    end

    def patch(ctx : RuleContext) : Hash(String, AnyData) | ServiceError
      id = ctx.id
      return ServiceError.bad_request("ID required for patch") unless id

      @mutex.synchronize do
        existing = @store[id]?
        return ServiceError.not_found unless existing

        record = existing.merge(ctx.data)
        record["id"] = id
        @store[id] = record
        record
      end
    end

    def remove(ctx : RuleContext) : Nil | ServiceError
      id = ctx.id
      return ServiceError.bad_request("ID required for remove") unless id

      deleted = @mutex.synchronize { @store.delete(id) }
      return ServiceError.not_found unless deleted
      nil
    end
  end
end
