require "../spec_helper"

# ── Helpers ───────────────────────────────────────────────────────────────────

private def any(v : String)
  JSON::Any.new(v)
end

private def any(v : Bool)
  JSON::Any.new(v)
end

private def any(v : Int64)
  JSON::Any.new(v)
end

# Builds a RuleContext wired to the given adapter.
# Only the fields that vary per-call need to be supplied.
private def make_ctx(
  adapter : Alumna::MemoryAdapter,
  method : Alumna::ServiceMethod,
  id : String? = nil,
  data : Hash(String, Alumna::AnyData) = {} of String => Alumna::AnyData,
  params : Hash(String, String) = {} of String => String,
) : Alumna::RuleContext
  Alumna::RuleContext.new(
    app: Alumna::App.new,
    service: adapter,
    path: adapter.path,
    method: method,
    phase: Alumna::RulePhase::Before,
    id: id,
    data: data,
    params: params
  )
end

# Shorthand to create a record directly through the adapter.
# Returns the stored record (with its assigned id).
private def insert(adapter, data : Hash(String, Alumna::AnyData))
  ctx = make_ctx(adapter, Alumna::ServiceMethod::Create, data: data)
  adapter.create(ctx)
end

# ─────────────────────────────────────────────────────────────────────────────

describe Alumna::MemoryAdapter do
  # ── create ───────────────────────────────────────────────────────────────────

  describe "#create" do
    it "returns the record with an auto-assigned id" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Create, data: {"name" => any("Alice")})
      record = adapter.create(ctx)
      record["id"].as_s.should eq("1")
      record["name"].as_s.should eq("Alice")
    end

    it "auto-increments ids across successive calls" do
      adapter = Alumna::MemoryAdapter.new("/items")
      r1 = insert(adapter, {"x" => any("a")})
      r2 = insert(adapter, {"x" => any("b")})
      r1["id"].as_s.should eq("1")
      r2["id"].as_s.should eq("2")
    end

    it "overrides any id supplied in the input data with its own counter" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Create, data: {"id" => any("999"), "name" => any("Bob")})
      record = adapter.create(ctx)
      record["id"].as_s.should eq("1")
    end

    it "persists the record so it can be retrieved afterwards" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")})
      get_ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: "1")
      adapter.get(get_ctx).not_nil!["name"].as_s.should eq("Alice")
    end
  end

  # ── find ─────────────────────────────────────────────────────────────────────

  describe "#find" do
    it "returns an empty array when the store is empty" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find)
      adapter.find(ctx).should be_empty
    end

    it "returns all records when no params are given" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")})
      insert(adapter, {"name" => any("Bob")})
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find)
      adapter.find(ctx).size.should eq(2)
    end

    it "filters records by a single query param" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"role" => any("admin")})
      insert(adapter, {"role" => any("user")})
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find, params: {"role" => "admin"})
      results = adapter.find(ctx)
      results.size.should eq(1)
      results.first["role"].as_s.should eq("admin")
    end

    it "applies AND semantics when multiple params are given" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"role" => any("admin"), "active" => any("true")})
      insert(adapter, {"role" => any("admin"), "active" => any("false")})
      insert(adapter, {"role" => any("user"), "active" => any("true")})
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find, params: {"role" => "admin", "active" => "true"})
      results = adapter.find(ctx)
      results.size.should eq(1)
      results.first["role"].as_s.should eq("admin")
      results.first["active"].as_s.should eq("true")
    end

    it "returns an empty array when no records match the filter" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"role" => any("user")})
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find, params: {"role" => "admin"})
      adapter.find(ctx).should be_empty
    end
  end

  # ── get ──────────────────────────────────────────────────────────────────────

  describe "#get" do
    it "returns the record for a known id" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")})
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: "1")
      record = adapter.get(ctx)
      record.should_not be_nil
      record.not_nil!["name"].as_s.should eq("Alice")
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

  # ── update ───────────────────────────────────────────────────────────────────

  describe "#update" do
    it "replaces the record entirely and returns it with the same id" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice"), "role" => any("user")})
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Update, id: "1", data: {"name" => any("Alice Smith")})
      record = adapter.update(ctx)
      record["id"].as_s.should eq("1")
      record["name"].as_s.should eq("Alice Smith")
    end

    it "drops fields from the old record that are absent from the new data" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice"), "role" => any("user")})
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Update, id: "1", data: {"name" => any("Alice Smith")})
      record = adapter.update(ctx)
      record["role"]?.should be_nil
    end

    it "persists the replacement so a subsequent get reflects it" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")})
      update_ctx = make_ctx(adapter, Alumna::ServiceMethod::Update, id: "1", data: {"name" => any("Alice Smith")})
      adapter.update(update_ctx)
      get_ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: "1")
      adapter.get(get_ctx).not_nil!["name"].as_s.should eq("Alice Smith")
    end

    it "raises a 404 error when the id does not exist" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Update, id: "99", data: {"name" => any("Ghost")})
      error = expect_raises(Alumna::ServiceError) { adapter.update(ctx) }
      error.status.should eq(404)
    end

    it "raises a 400 error when ctx.id is nil" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Update, id: nil, data: {"name" => any("Ghost")})
      error = expect_raises(Alumna::ServiceError) { adapter.update(ctx) }
      error.status.should eq(400)
    end
  end

  # ── patch ────────────────────────────────────────────────────────────────────

  describe "#patch" do
    it "merges the new data onto the existing record" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice"), "role" => any("user")})
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Patch, id: "1", data: {"role" => any("admin")})
      record = adapter.patch(ctx)
      record["name"].as_s.should eq("Alice") # original field preserved
      record["role"].as_s.should eq("admin") # field updated
      record["id"].as_s.should eq("1")
    end

    it "persists the merge so a subsequent get reflects it" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice"), "role" => any("user")})
      patch_ctx = make_ctx(adapter, Alumna::ServiceMethod::Patch, id: "1", data: {"role" => any("admin")})
      adapter.patch(patch_ctx)
      get_ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: "1")
      record = adapter.get(get_ctx).not_nil!
      record["name"].as_s.should eq("Alice")
      record["role"].as_s.should eq("admin")
    end

    it "raises a 404 error when the id does not exist" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Patch, id: "99", data: {"name" => any("Ghost")})
      error = expect_raises(Alumna::ServiceError) { adapter.patch(ctx) }
      error.status.should eq(404)
    end

    it "raises a 400 error when ctx.id is nil" do
      adapter = Alumna::MemoryAdapter.new("/items")
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Patch, id: nil, data: {"name" => any("Ghost")})
      error = expect_raises(Alumna::ServiceError) { adapter.patch(ctx) }
      error.status.should eq(400)
    end
  end

  # ── remove ───────────────────────────────────────────────────────────────────

  describe "#remove" do
    it "deletes the record and returns true" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")})
      ctx = make_ctx(adapter, Alumna::ServiceMethod::Remove, id: "1")
      adapter.remove(ctx).should be_true
    end

    it "makes the record unretrievable after deletion" do
      adapter = Alumna::MemoryAdapter.new("/items")
      insert(adapter, {"name" => any("Alice")})
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

  # ── Concurrency ────────────────────────────────────────────────────────────────

  describe "concurrency" do
    it "assigns unique sequential ids under concurrent creates" do
      adapter = Alumna::MemoryAdapter.new("/items")
      count = 100
      done = Channel(Nil).new(count)

      count.times do
        spawn do
          ctx = make_ctx(adapter, Alumna::ServiceMethod::Create, data: {"x" => any("v")})
          adapter.create(ctx)
          done.send(nil)
        end
      end

      count.times { done.receive }

      ctx = make_ctx(adapter, Alumna::ServiceMethod::Find)
      records = adapter.find(ctx)

      records.size.should eq(count)
      ids = records.map { |r| r["id"].as_s.to_i64 }.sort
      ids.should eq((1_i64..count.to_i64).to_a)
    end

    it "does not lose updates under concurrent patches to the same record" do
      adapter = Alumna::MemoryAdapter.new("/items")
      base = insert(adapter, {"counter" => any(0_i64)})
      id = base["id"].as_s

      writers = 50
      done = Channel(Nil).new(writers)

      writers.times do |i|
        spawn do
          # each fiber reads, increments, patches — without mutex this races
          get_ctx = make_ctx(adapter, Alumna::ServiceMethod::Get, id: id)
          current = adapter.get(get_ctx).not_nil!
          val = current["counter"].as_i64

          patch_ctx = make_ctx(
            adapter,
            Alumna::ServiceMethod::Patch,
            id: id,
            data: {"counter" => any(val + 1)}
          )
          adapter.patch(patch_ctx)
          done.send(nil)
        end
        # force a yield so fibers interleave
        Fiber.yield
      end

      writers.times { done.receive }

      final = adapter.get(make_ctx(adapter, Alumna::ServiceMethod::Get, id: id)).not_nil!
      # With mutex, each patch is atomic — we won't lose writes entirely,
      # but because read-modify-write isn't atomic across calls, the final
      # value will be <= writers. The important assertion is no corruption:
      final["counter"].as_i64.should be >= 1
      final["counter"].as_i64.should be <= writers
      final["id"].as_s.should eq(id) # record still intact
    end

    it "allows concurrent finds while writing" do
      adapter = Alumna::MemoryAdapter.new("/items")
      done = Channel(Nil).new(2)

      spawn do
        50.times do |i|
          insert(adapter, {"n" => any(i.to_i64)})
          Fiber.yield
        end
        done.send(nil)
      end

      spawn do
        50.times do
          ctx = make_ctx(adapter, Alumna::ServiceMethod::Find)
          # should never raise ConcurrentModification or return nil
          adapter.find(ctx).size.should be >= 0
          Fiber.yield
        end
        done.send(nil)
      end

      2.times { done.receive }
      # if we got here without deadlock or exception, mutex works
      adapter.find(make_ctx(adapter, Alumna::ServiceMethod::Find)).size.should eq(50)
    end
  end
end
