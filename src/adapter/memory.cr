module Alumna
  class MemoryAdapter < Service
    @store : Hash(String, Hash(String, AnyData))
    @next_id : Int64
    @mutex : Mutex

    def initialize(schema : Schema? = nil)
      super(schema)
      @store = {} of String => Hash(String, AnyData)
      @next_id = 1_i64
      @mutex = Mutex.new
    end

    private def compare_values(a : AnyData, b : AnyData) : Int32
      # Handle nil / missing fields (nils come first)
      return 0 if a.nil? && b.nil?
      return -1 if a.nil?
      return 1 if b.nil?

      # Safely compare numbers by arithmetic value (Int64 and Float64)
      if (a.is_a?(Int64) || a.is_a?(Float64)) && (b.is_a?(Int64) || b.is_a?(Float64))
        # Float64#<=> returns Int32? (returns nil when comparing with NaN)
        # We fallback to 0 (equal) to satisfy the strict Int32 return requirement.
        return (a.as(Int64 | Float64) <=> b.as(Int64 | Float64)) || 0
      end

      # Compare identical string or boolean types
      if a.class == b.class
        case a
        when String
          return a <=> b.as(String)
        when Bool
          return (a ? 1 : 0) <=> (b.as(Bool) ? 1 : 0)
        end
      end

      # Deterministic fallback for mismatched types or complex structures
      a.to_s <=> b.to_s
    end

    def find(ctx : RuleContext) : Array(Hash(String, AnyData))
      @mutex.synchronize do
        q = ctx.query
        records = @store.values

        # 1) filters (old behaviour, now via q.filters)
        unless q.filters.empty?
          records = records.select do |rec|
            q.filters.all? { |k, v| rec[k]?.try(&.to_s) == v }
          end
        end

        # 2) sort
        if sort = q.sort
          records.sort! do |a, b|
            sort.reduce(0) do |cmp, (field, dir)|
              next cmp if cmp != 0
              compare_values(a[field]?, b[field]?) * dir
            end
          end
        end

        # 3) skip + limit
        records = records.skip(q.skip || 0)
        if limit = q.limit
          records = records.first(limit)
        end

        # 4) select (always keep id for sanity)
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
