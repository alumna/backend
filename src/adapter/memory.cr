module Alumna
  class MemoryAdapter < Service
    @store : Hash(String, Hash(String, AnyData))
    @next_id : Int64
    @mutex : Mutex

    def initialize(path : String, schema : Schema? = nil)
      super(path, schema)
      @store = {} of String => Hash(String, AnyData)
      @next_id = 1_i64
      @mutex = Mutex.new
    end

    def find(ctx : RuleContext) : Array(Hash(String, AnyData))
      @mutex.synchronize do
        records = @store.values
        return records.to_a if ctx.params.empty?
        records.select do |record|
          ctx.params.all? do |key, value|
            record[key]?.try(&.raw.as?(String)) == value
          end
        end.to_a
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
        record = ctx.data.merge({"id" => AnyData.new(id)})
        @store[id] = record
        record
      end
    end

    def update(ctx : RuleContext) : Hash(String, AnyData)
      @mutex.synchronize do
        id = ctx.id || raise ServiceError.bad_request("ID required for update")
        raise ServiceError.not_found unless @store.has_key?(id)
        record = ctx.data.merge({"id" => AnyData.new(id)})
        @store[id] = record
        record
      end
    end

    def patch(ctx : RuleContext) : Hash(String, AnyData)
      @mutex.synchronize do
        id = ctx.id || raise ServiceError.bad_request("ID required for patch")
        existing = @store[id]? || raise ServiceError.not_found
        record = existing.merge(ctx.data).merge({"id" => AnyData.new(id)})
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
