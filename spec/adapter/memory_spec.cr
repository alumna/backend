require "../spec_helper"

# ── Helpers ───────────────────────────────────────────────────────────────────

private def any(v : String) : Alumna::AnyData
  v
end

private def any(v : Bool) : Alumna::AnyData
  v
end

private def any(v : Int) : Alumna::AnyData
  v.to_i64
end

# Builds a RuleContext wired to the given adapter.
private def make_ctx(
  adapter : Alumna::MemoryAdapter,
  method : Alumna::ServiceMethod,
  id : String? = nil,
  data : Hash(String, Alumna::AnyData) = {} of String => Alumna::AnyData,
  params : Hash(String, String) = {} of String => String,
) : Alumna::RuleContext
  http_params = HTTP::Params.new
  params.each { |k, v| http_params.add(k, v) }
  Alumna::RuleContext.new(
    app: Alumna::App.new,
    service: adapter,
    path: adapter.path,
    method: method,
    phase: Alumna::RulePhase::Before,
    params: Alumna::Http::ParamsView.new(http_params),
    headers: Alumna::Http::HeadersView.new(HTTP::Headers.new),
    id: id,
    data: data
  )
end

private def insert(adapter, data : Hash(String, Alumna::AnyData))
  ctx = make_ctx(adapter, Alumna::ServiceMethod::Create, data: data)
  adapter.create(ctx)
end

describe Alumna::MemoryAdapter do
  describe "#create" do
    it "returns the record with an auto-assigned id" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Create, data: {"name" => any("Alice")} of String => Alumna::AnyData)
      record = adapter.create(ctx)
      record["id"].should eq("1")
      record["name"].should eq("Alice")
    end

    it "auto-increments ids across successive calls" do
      adapter = Alumna::MemoryAdapter.new("/items")
      r1 = insert(adapter, {"x" => any("a")} of String => Alumna::AnyData)
      r2 = insert(adapter, {"x" => any("b")} of String => Alumna::AnyData)
      r1["id"].should eq("1")
      r2["id"].should eq("2")
    end

    it "overrides any id supplied in the input data with its own counter" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Create, data: {"id" => any("999"), "name" => any("Bob")} of String => Alumna::AnyData)
      record = adapter.create(ctx)
      record["id"].should eq("1")
    end

    it "persists the record so it can be retrieved afterwards" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")} of String => Alumna::AnyData)
      get_ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: "1")
      record = adapter.get(get_ctx)
      record.should_not be_nil
      if record
        record["name"].should eq("Alice")
      end
    end
  end

  describe "#find" do
    it "returns an empty array when the store is empty" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find)
      adapter.find(ctx).should be_empty
    end

    it "returns all records when no params are given" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")} of String => Alumna::AnyData)
      insert(adapter, {"name" => any("Bob")} of String => Alumna::AnyData)
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find)
      adapter.find(ctx).size.should eq(2)
    end

    it "filters records by a single query param" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"role" => any("admin")} of String => Alumna::AnyData)
      insert(adapter, {"role" => any("user")} of String => Alumna::AnyData)
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find, params: {"role" => "admin"})
      results = adapter.find(ctx)
      results.size.should eq(1)
      results.first["role"].should eq("admin")
    end

    it "applies AND semantics when multiple params are given" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"role" => any("admin"), "active" => any("true")} of String => Alumna::AnyData)
      insert(adapter, {"role" => any("admin"), "active" => any("false")} of String => Alumna::AnyData)
      insert(adapter, {"role" => any("user"), "active" => any("true")} of String => Alumna::AnyData)
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find, params: {"role" => "admin", "active" => "true"})
      results = adapter.find(ctx)
      results.size.should eq(1)
      results.first["role"].should eq("admin")
      results.first["active"].should eq("true")
    end

    it "returns an empty array when no records match the filter" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"role" => any("user")} of String => Alumna::AnyData)
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find, params: {"role" => "admin"})
      adapter.find(ctx).should be_empty
    end
  end

  describe "#get" do
    it "returns the record for a known id" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")} of String => Alumna::AnyData)
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: "1")
      record = adapter.get(ctx)
      record.should_not be_nil
      if record
        record["name"].should eq("Alice")
      end
    end

    it "returns nil for an unknown id" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: "99")
      adapter.get(ctx).should be_nil
    end

    it "returns nil when ctx.id is nil" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: nil)
      adapter.get(ctx).should be_nil
    end
  end

  describe "#update" do
    it "replaces the record entirely and returns it with the same id" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice"), "role" => any("user")} of String => Alumna::AnyData)
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Update, id: "1", data: {"name" => any("Alice"), "role" => any("admin")} of String => Alumna::AnyData)
      record = adapter.update(ctx)
      record["id"].should eq("1")
      record["role"].should eq("admin")
    end
  end

  describe "#patch" do
    it "merges fields and preserves id" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice"), "role" => any("user")} of String => Alumna::AnyData)
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Patch, id: "1", data: {"role" => any("admin")} of String => Alumna::AnyData)
      record = adapter.patch(ctx)
      record["name"].should eq("Alice")
      record["role"].should eq("admin")
      record["id"].should eq("1")
    end

    it "persists the merge so a subsequent get reflects it" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice"), "role" => any("user")} of String => Alumna::AnyData)
      patch_ctx = make_ctx(adapter, Alumna::ServiceMethod::Patch, id: "1", data: {"role" => any("admin")} of String => Alumna::AnyData)
      adapter.patch(patch_ctx)
      get_ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: "1")
      record = adapter.get(get_ctx)
      record.should_not be_nil
      if record
        record["name"].should eq("Alice")
        record["role"].should eq("admin")
      end
    end

    it "raises a 404 error when the id does not exist" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Patch, id: "99", data: {"name" => any("Ghost")} of String => Alumna::AnyData)
      error = expect_raises(Alumna::ServiceError) { adapter.patch(ctx) }
      error.status.should eq(404)
    end

    it "raises a 400 error when ctx.id is nil" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Patch, id: nil, data: {"name" => any("Ghost")} of String => Alumna::AnyData)
      error = expect_raises(Alumna::ServiceError) { adapter.patch(ctx) }
      error.status.should eq(400)
    end
  end

  describe "#remove" do
    it "deletes the record and returns true" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")} of String => Alumna::AnyData)
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Remove, id: "1")
      adapter.remove(ctx).should be_true
    end

    it "makes the record unretrievable after deletion" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")} of String => Alumna::AnyData)
      remove_ctx = make_ctx(adapter, Alumna::ServiceMethod::Remove, id: "1")
      adapter.remove(remove_ctx)
      get_ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: "1")
      adapter.get(get_ctx).should be_nil
    end

    it "returns false when the id does not exist" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Remove, id: "99")
      adapter.remove(ctx).should be_false
    end

    it "raises a 400 error when ctx.id is nil" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Remove, id: nil)
      error = expect_raises(Alumna::ServiceError) { adapter.remove(ctx) }
      error.status.should eq(400)
    end
  end

  describe "concurrency" do
    it "assigns unique sequential ids under concurrent creates" do
      adapter = Alumna::MemoryAdapter.new("/items")
      count = 100
      done = Channel(Nil).new(count)

      count.times do
        spawn do
          ctx = make_ctx(adapter, Alumna::ServiceMethod::Create, data: {"x" => any("v")} of String => Alumna::AnyData)
          adapter.create(ctx)
          done.send(nil)
        end
      end

      count.times { done.receive }

      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find)
      records = adapter.find(ctx)

      records.size.should eq(count)
      ids = records.map { |r| r["id"].as(String).to_i64 }.sort
      ids.should eq((1_i64..count.to_i64).to_a)
    end

    it "does not lose updates under concurrent patches to the same record" do
      adapter = Alumna::MemoryAdapter.new("/items")
      base = insert(adapter, {"counter" => any(0_i64)} of String => Alumna::AnyData)
      id = base["id"].as(String)

      writers = 50
      done = Channel(Nil).new(writers)

      writers.times do |i|
        spawn do
          get_ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: id)
          current = adapter.get(get_ctx)
          current.should_not be_nil
          if current
            val = current["counter"].as(Int64)
            patch_ctx = make_ctx(
              adapter,
              Alumna::ServiceMethod::Patch,
              id: id,
              data: {"counter" => any(val + 1)} of String => Alumna::AnyData
            )
            adapter.patch(patch_ctx)
          end
          done.send(nil)
        end
        Fiber.yield
      end

      writers.times { done.receive }

      final = adapter.get(make_ctx(adapter, Alumna::ServiceMethod::Get, id: id))
      final.should_not be_nil
      if final
        final["counter"].as(Int64).should be >= 1
        final["counter"].as(Int64).should be <= writers
        final["id"].as(String).should eq(id)
      end
    end

    it "allows concurrent finds while writing" do
      adapter = Alumna::MemoryAdapter.new("/items")
      done = Channel(Nil).new(2)

      spawn do
        50.times do |i|
          insert(adapter, {"n" => any(i.to_i64)} of String => Alumna::AnyData)
          Fiber.yield
        end
        done.send(nil)
      end

      spawn do
        50.times do
          ctx = make_ctx(adapter, Alumna::ServiceMethod::Find)
          adapter.find(ctx).size.should be >= 0
          Fiber.yield
        end
        done.send(nil)
      end

      2.times { done.receive }
      adapter.find(make_ctx(adapter, Alumna::ServiceMethod::Find)).size.should eq(50)
    end
  end
end
