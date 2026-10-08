require "digest/sha256"

module Alumna
  # Get + find cache. Attach:
  #
  #   rule = Alumna.cache(cache, ttl: 30.seconds)
  #   before rule, on: :read
  #   after rule
  #
  # Get: one key per id. Write-through set. Miss fill set_nx. Remove delete.
  # Find: key is generation + query hash. Writes incr the collection generation.
  # Old find keys stay until TTL. skip_providers applies to get and find.
  # Internal writes still update get keys and bump find generation.
  # Store-down is ServiceError.internal. Do not fill. Do not write-through.
  private module CacheRule
    DEFAULT_SKIP = ["internal"]
    HIT_KEY      = "alumna.cache.hit"
    FIND_GEN_KEY = "alumna.cache.fgen"

    def self.get_key(path : String, id : String) : String
      String.build do |io|
        io << "alumna:get:" << path << ':' << id
      end
    end

    def self.find_gen_key(path : String) : String
      String.build do |io|
        io << "alumna:fgen:" << path
      end
    end

    def self.find_key(path : String, gen : Int64, fingerprint : String) : String
      String.build do |io|
        io << "alumna:find:" << gen << ':' << path << ':' << fingerprint
      end
    end

    def self.find_gen(cache : Cache, path : String) : Int64 | StoreError
      bytes = cache.get(find_gen_key(path))
      return bytes if bytes.is_a?(StoreError)
      return 0_i64 unless bytes
      String.new(bytes).to_i64? || 0_i64
    end

    # One buffer for JSON bytes that are copied out before the lock is released.
    @@json_io = IO::Memory.new(128)
    @@json_mu = Sync::Mutex.new

    def self.query_fingerprint(query : Query) : String
      # LCOV_EXCL_START - kcov misses Sync::Mutex#lock and the following begin
      @@json_mu.lock
      begin
      # LCOV_EXCL_STOP
        @@json_io.clear
        write_canonical(@@json_io, query)
        Digest::SHA256.hexdigest(@@json_io.to_slice)
      ensure
        @@json_mu.unlock
      end
    end

    # Same bytes as the previous `JSON.build` document. The hash of this text is the find key.
    def self.write_canonical(io : IO, query : Query) : Nil
      io << "{\"f\":{"
      first_field = true
      query.filters.keys.sort.each do |field|
        io << ',' unless first_field
        first_field = false
        JsonHelper.write_string(io, field)
        io << ":["
        first_cond = true
        query.filters[field].each do |cond|
          io << ',' unless first_cond
          first_cond = false
          io << '['
          JsonHelper.write_string(io, cond.op.to_s)
          io << ','
          val = cond.value
          if val.is_a?(Array)
            io << '['
            index = 0
            while index < val.size
              io << ',' if index > 0
              JsonHelper.write_string(io, val[index])
              index &+= 1
            end
            io << ']'
          else
            JsonHelper.write_string(io, val)
          end
          io << ']'
        end
        io << ']'
      end
      io << "},\"l\":"
      if limit = query.limit
        io << limit
      else
        io << "null"
      end
      io << ",\"k\":"
      if skip = query.skip
        io << skip
      else
        io << "null"
      end
      io << ",\"o\":"
      if sort = query.sort
        io << '['
        index = 0
        while index < sort.size
          io << ',' if index > 0
          field, dir = sort[index]
          io << '['
          JsonHelper.write_string(io, field)
          io << ','
          io << dir
          io << ']'
          index &+= 1
        end
        io << ']'
      else
        io << "null"
      end
      io << ",\"s\":"
      if sel = query.select
        io << '['
        ordered = sel.sort
        index = 0
        while index < ordered.size
          io << ',' if index > 0
          JsonHelper.write_string(io, ordered[index])
          index &+= 1
        end
        io << ']'
      else
        io << "null"
      end
      io << '}'
    end

    def self.encode(record : Hash(String, AnyData)) : Bytes
      copy_json { |io| JsonHelper.write(io, record) }
    end

    def self.encode_list(records : Array(Hash(String, AnyData))) : Bytes
      copy_json do |io|
        io << '['
        index = 0
        while index < records.size
          io << ',' if index > 0
          JsonHelper.write(io, records[index])
          index &+= 1
        end
        io << ']'
      end
    end

    def self.copy_json(& : IO ->) : Bytes
      # LCOV_EXCL_START - kcov misses Sync::Mutex#lock and the following begin
      @@json_mu.lock
      begin
      # LCOV_EXCL_STOP
        @@json_io.clear
        yield @@json_io
        bytes = Bytes.new(@@json_io.bytesize)
        bytes.copy_from(@@json_io.to_slice)
        bytes
      ensure
        @@json_mu.unlock
      end
    end

    def self.decode(bytes : Bytes) : Hash(String, AnyData)?
      decoded = JsonHelper.from_string(String.new(bytes))
      decoded.as?(Hash(String, AnyData))
    rescue JSON::ParseException
      nil
    end

    def self.decode_list(bytes : Bytes) : Array(Hash(String, AnyData))?
      decoded = JsonHelper.from_string(String.new(bytes))
      arr = decoded.as?(Array(AnyData))
      return nil unless arr
      out = Array(Hash(String, AnyData)).new(arr.size)
      arr.each do |item|
        row = item.as?(Hash(String, AnyData))
        return nil unless row
        out << row
      end
      out
    rescue JSON::ParseException
      nil
    end

    def self.id_from(ctx : RuleContext) : String?
      if id = ctx.id
        return id unless id.empty?
      end
      record = ctx.result.as?(Hash(String, AnyData))
      return nil unless record
      raw = record["id"]?
      return nil unless raw.is_a?(String)
      raw.empty? ? nil : raw
    end

    def self.mutates?(method : ServiceMethod) : Bool
      method.create? || method.update? || method.patch? || method.remove?
    end

    def self.down(error : StoreError) : ServiceError
      ServiceError.internal(error.message)
    end
  end

  def self.cache(
    cache : Cache,
    ttl : Time::Span,
    skip_providers : Array(String) = CacheRule::DEFAULT_SKIP,
  ) : Rule
    raise ArgumentError.new("cache ttl must be > 0") if ttl <= Time::Span.zero

    Rule.new do |ctx|
      if ctx.phase.before?
        next nil if skip_providers.includes?(ctx.provider)
        if ctx.method.get?
          id = ctx.id
          next nil unless id && !id.empty?
          key = CacheRule.get_key(ctx.service.path, id)
          got = cache.get(key)
          next CacheRule.down(got) if got.is_a?(StoreError)
          if bytes = got
            if record = CacheRule.decode(bytes)
              ctx.store[CacheRule::HIT_KEY] = true
              ctx.result = record
            else
              deleted = cache.delete(key)
              next CacheRule.down(deleted) if deleted.is_a?(StoreError)
            end
          end
        elsif ctx.method.find?
          gen = CacheRule.find_gen(cache, ctx.service.path)
          next CacheRule.down(gen) if gen.is_a?(StoreError)
          ctx.store[CacheRule::FIND_GEN_KEY] = gen
          key = CacheRule.find_key(ctx.service.path, gen, CacheRule.query_fingerprint(ctx.query))
          got = cache.get(key)
          next CacheRule.down(got) if got.is_a?(StoreError)
          if bytes = got
            if list = CacheRule.decode_list(bytes)
              ctx.store[CacheRule::HIT_KEY] = true
              ctx.result = list
            else
              deleted = cache.delete(key)
              next CacheRule.down(deleted) if deleted.is_a?(StoreError)
            end
          end
        end
      elsif ctx.phase.after?
        if ctx.method.get?
          next nil if skip_providers.includes?(ctx.provider)
          id = ctx.id
          next nil unless id && !id.empty?
          next nil if ctx.store[CacheRule::HIT_KEY]?
          record = ctx.result.as?(Hash(String, AnyData))
          next nil unless record
          wrote = cache.set_nx(CacheRule.get_key(ctx.service.path, id), CacheRule.encode(record), ttl)
          next CacheRule.down(wrote) if wrote.is_a?(StoreError)
        elsif ctx.method.find?
          next nil if skip_providers.includes?(ctx.provider)
          next nil if ctx.store[CacheRule::HIT_KEY]?
          observed = ctx.store[CacheRule::FIND_GEN_KEY]?.as?(Int64)
          next nil if observed.nil?
          now = CacheRule.find_gen(cache, ctx.service.path)
          next CacheRule.down(now) if now.is_a?(StoreError)
          next nil unless observed == now
          list = ctx.result.as?(Array(Hash(String, AnyData)))
          next nil unless list
          fp = CacheRule.query_fingerprint(ctx.query)
          wrote = cache.set_nx(CacheRule.find_key(ctx.service.path, now, fp), CacheRule.encode_list(list), ttl)
          next CacheRule.down(wrote) if wrote.is_a?(StoreError)
        elsif CacheRule.mutates?(ctx.method)
          bumped = cache.incr(CacheRule.find_gen_key(ctx.service.path))
          next CacheRule.down(bumped) if bumped.is_a?(StoreError)
          if ctx.method.remove?
            id = ctx.id
            if id && !id.empty?
              deleted = cache.delete(CacheRule.get_key(ctx.service.path, id))
              next CacheRule.down(deleted) if deleted.is_a?(StoreError)
            end
          else
            record = ctx.result.as?(Hash(String, AnyData))
            if record
              if id = CacheRule.id_from(ctx)
                written = cache.set(CacheRule.get_key(ctx.service.path, id), CacheRule.encode(record), ttl)
                next CacheRule.down(written) if written.is_a?(StoreError)
              end
            end
          end
        end
      end
      nil
    end
  end
end
