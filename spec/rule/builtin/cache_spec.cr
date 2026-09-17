require "../../spec_helper"
require "../../../src/testing"

private def get_cache_key(id : String)
  "alumna:get:/posts:" + id
end

private def cache_schema
  Alumna::Schema.new
    .str("title", required_on: [:create, :update], min_length: 1)
end

private def cache_app(cache : Alumna::Cache, ttl : Time::Span = 1.hour, skip_providers : Array(String) = ["internal"])
  rule = Alumna.cache(cache, ttl: ttl, skip_providers: skip_providers)
  app = Alumna::App.new
  app.use "/posts", Alumna.memory(cache_schema) {
    before rule, on: :read
    after rule
  }
  {app, rule}
end

private class CacheGetCounter < Alumna::MemoryAdapter
  getter get_count : Int32 = 0

  def get(ctx)
    @get_count += 1
    super
  end
end

private class CacheFindCounter < Alumna::MemoryAdapter
  getter find_count : Int32 = 0

  def find(ctx)
    @find_count += 1
    super
  end
end

private class CacheKeySpy < Alumna::MemoryCache
  getter last_get : String = ""

  def get(key : String) : Bytes?
    @last_get = key
    super
  end
end

describe "Alumna.cache" do
  it "rejects a non-positive ttl" do
    expect_raises(ArgumentError, "cache ttl must be > 0") do
      Alumna.cache(Alumna::MemoryCache.new, ttl: Time::Span.zero)
    end
  end

  it "writes through on create so the first get is a hit" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    posts = CacheGetCounter.new(cache_schema)
    posts.before(rule, on: :read)
    posts.after(rule)
    app = Alumna::App.new
    app.use "/posts", posts
    client = Alumna::Testing::AppClient.new(app)
    id = client.post("/posts", body: %({"title":"A"})).json_hash["id"].as(String)
    client.get("/posts/#{id}").json_hash["title"].should eq("A")
    posts.get_count.should eq(0)
  end

  it "writes through on patch so get sees the new title" do
    cache = Alumna::MemoryCache.new
    app, _ = cache_app(cache)
    client = Alumna::Testing::AppClient.new(app)
    id = client.post("/posts", body: %({"title":"A"})).json_hash["id"].as(String)
    client.patch("/posts/#{id}", body: %({"title":"B"}))
    client.get("/posts/#{id}").json_hash["title"].should eq("B")
  end

  it "writes through on update and deletes on remove" do
    cache = Alumna::MemoryCache.new
    app, _ = cache_app(cache)
    client = Alumna::Testing::AppClient.new(app)
    id = client.post("/posts", body: %({"title":"A"})).json_hash["id"].as(String)
    client.put("/posts/#{id}", body: %({"title":"C"}))
    client.get("/posts/#{id}").json_hash["title"].should eq("C")
    client.delete("/posts/#{id}")
    client.get("/posts/#{id}").status.should eq(404)
    cache.get(get_cache_key(id)).should be_nil
  end

  it "caches find and invalidates after create" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    posts = CacheFindCounter.new(cache_schema)
    posts.before(rule, on: :read)
    posts.after(rule)
    app = Alumna::App.new
    app.use "/posts", posts
    client = Alumna::Testing::AppClient.new(app)
    client.post("/posts", body: %({"title":"A"}))
    client.get("/posts").json_array.size.should eq(1)
    posts.find_count.should eq(1)
    client.get("/posts").json_array.size.should eq(1)
    posts.find_count.should eq(1)
    client.post("/posts", body: %({"title":"B"}))
    client.get("/posts").json_array.size.should eq(2)
    posts.find_count.should eq(2)
  end

  it "does not cache a 404 get" do
    cache = Alumna::MemoryCache.new
    app, _ = cache_app(cache)
    client = Alumna::Testing::AppClient.new(app)
    client.get("/posts/1").status.should eq(404)
    cache.size.should eq(0)
  end

  it "skips internal ctx.call by default" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    posts = CacheGetCounter.new(cache_schema)
    posts.before(rule, on: :read)
    posts.after(rule)
    app = Alumna::App.new
    app.use "/posts", posts
    app.use "/proxy", Alumna.memory(cache_schema) {
      before on: :get do |ctx|
        result, err = ctx.call("/posts/#{ctx.id}", :get)
        ctx.result = result
        err
      end
    }
    client = Alumna::Testing::AppClient.new(app)
    id = client.post("/posts", body: %({"title":"A"})).json_hash["id"].as(String)
    client.get("/posts/#{id}")
    posts.get_count.should eq(0)
    client.get("/proxy/#{id}")
    posts.get_count.should eq(1)
  end

  it "expires a get entry after ttl" do
    cache = Alumna::MemoryCache.new
    app, _ = cache_app(cache, ttl: 1.nanosecond)
    client = Alumna::Testing::AppClient.new(app)
    id = client.post("/posts", body: %({"title":"A"})).json_hash["id"].as(String)
    sleep 1.milliseconds
    cache.get(get_cache_key(id)).should be_nil
  end

  it "ignores find" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    ctx = Alumna::Testing.build_ctx(method: Alumna::ServiceMethod::Find, id: "1", phase: Alumna::RulePhase::After)
    ctx.result = [Alumna.hash(title: "A")]
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "writes through on create from the result id" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Create,
      phase: Alumna::RulePhase::After,
    )
    ctx.result = Alumna.hash(id: "9", title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.get("alumna:get:/posts:9").should_not be_nil
  end

  it "fills with set_nx after a get miss" do
    cache = Alumna::MemoryCache.new
    app, _ = cache_app(cache)
    client = Alumna::Testing::AppClient.new(app)
    id = client.post("/posts", body: %({"title":"A"})).json_hash["id"].as(String)
    cache.delete(get_cache_key(id))
    client.get("/posts/#{id}").json_hash["title"].should eq("A")
    cache.get(get_cache_key(id)).should_not be_nil
  end

  it "skips write-through when the record has no id" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Create,
      phase: Alumna::RulePhase::After,
    )
    ctx.result = Alumna.hash(title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.get("alumna:fgen:/posts").should eq("1".to_slice)
    cache.get("alumna:get:/posts:1").should be_nil
  end

  it "skips write-through when the result id is empty" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Create,
      phase: Alumna::RulePhase::After,
    )
    ctx.result = Alumna.hash(id: "", title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.get("alumna:fgen:/posts").should eq("1".to_slice)
    cache.size.should eq(1)
  end

  it "skips write-through when the result is not a hash" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Patch,
      id: "1",
      phase: Alumna::RulePhase::After,
    )
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.get("alumna:fgen:/posts").should eq("1".to_slice)
    cache.size.should eq(1)
  end

  it "writes through on an internal patch" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Patch,
      id: "1",
      phase: Alumna::RulePhase::After,
      provider: "internal",
    )
    ctx.result = Alumna.hash(id: "1", title: "B")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.get("alumna:get:/posts:1").should_not be_nil
  end

  it "skips remove without an id" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Remove,
      phase: Alumna::RulePhase::After,
    )
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.get("alumna:fgen:/posts").should eq("1".to_slice)
  end

  it "skips a listed provider on get" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Get,
      id: "1",
      phase: Alumna::RulePhase::After,
      provider: "internal",
    )
    ctx.result = Alumna.hash(title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "skips get without an id" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    ctx = Alumna::Testing.build_ctx(method: Alumna::ServiceMethod::Get, phase: Alumna::RulePhase::After)
    ctx.result = Alumna.hash(title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "skips get with an empty id" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    ctx = Alumna::Testing.build_ctx(method: Alumna::ServiceMethod::Get, id: "", phase: Alumna::RulePhase::After)
    ctx.result = Alumna.hash(title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "treats corrupt cache bytes as a miss" do
    cache = Alumna::MemoryCache.new
    cache.set("alumna:get:/posts:1", "not-json".to_slice)
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Get,
      id: "1",
      phase: Alumna::RulePhase::Before,
    )
    Alumna::Testing.run_rule(rule, ctx: ctx)
    ctx.result_set?.should be_false
    cache.get("alumna:get:/posts:1").should be_nil
  end

  it "treats a non-object JSON value as a miss" do
    cache = Alumna::MemoryCache.new
    cache.set("alumna:get:/posts:1", "[1]".to_slice)
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Get,
      id: "1",
      phase: Alumna::RulePhase::Before,
    )
    Alumna::Testing.run_rule(rule, ctx: ctx)
    ctx.result_set?.should be_false
    cache.get("alumna:get:/posts:1").should be_nil
  end

  it "does not write on after when the before phase was a hit" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Get,
      id: "1",
      phase: Alumna::RulePhase::After,
    )
    ctx.store["alumna.cache.hit"] = true
    ctx.result = Alumna.hash(title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "fill uses set_nx so it does not overwrite a concurrent write" do
    cache = Alumna::MemoryCache.new
    cache.set("alumna:get:/posts:1", %({"title":"B"}).to_slice)
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Get,
      id: "1",
      phase: Alumna::RulePhase::After,
    )
    ctx.result = Alumna.hash(title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    String.new(cache.get("alumna:get:/posts:1").as(Bytes)).should contain("B")
  end

  it "does not write a non-hash after get result" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Get,
      id: "1",
      phase: Alumna::RulePhase::After,
    )
    ctx.result = [] of Hash(String, Alumna::AnyData)
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "ignores the error phase" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Get,
      id: "1",
      phase: Alumna::RulePhase::Error,
    )
    ctx.result = Alumna.hash(title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "uses separate find keys for different queries" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    posts = CacheFindCounter.new(cache_schema)
    posts.before(rule, on: :read)
    posts.after(rule)
    app = Alumna::App.new
    app.use "/posts", posts
    client = Alumna::Testing::AppClient.new(app)
    client.post("/posts", body: %({"title":"A"}))
    client.post("/posts", body: %({"title":"B"}))
    client.get("/posts").json_array.size.should eq(2)
    client.get("/posts?$limit=1").json_array.size.should eq(1)
    posts.find_count.should eq(2)
    client.get("/posts?$limit=1").json_array.size.should eq(1)
    posts.find_count.should eq(2)
  end

  it "invalidates find after patch and remove" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    posts = CacheFindCounter.new(cache_schema)
    posts.before(rule, on: :read)
    posts.after(rule)
    app = Alumna::App.new
    app.use "/posts", posts
    client = Alumna::Testing::AppClient.new(app)
    id = client.post("/posts", body: %({"title":"A"})).json_hash["id"].as(String)
    client.get("/posts")
    posts.find_count.should eq(1)
    client.patch("/posts/#{id}", body: %({"title":"B"}))
    client.get("/posts").json_array[0].as(Hash(String, Alumna::AnyData))["title"].should eq("B")
    posts.find_count.should eq(2)
    client.delete("/posts/#{id}")
    client.get("/posts").json_array.size.should eq(0)
    posts.find_count.should eq(3)
    client.get("/posts").json_array.size.should eq(0)
    posts.find_count.should eq(3)
  end

  it "skips internal find by default" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    posts = CacheFindCounter.new(cache_schema)
    posts.before(rule, on: :read)
    posts.after(rule)
    app = Alumna::App.new
    app.use "/posts", posts
    app.use "/proxy", Alumna.memory(cache_schema) {
      before on: :find do |ctx|
        result, err = ctx.call("/posts", :find)
        ctx.result = result
        err
      end
    }
    client = Alumna::Testing::AppClient.new(app)
    client.post("/posts", body: %({"title":"A"}))
    client.get("/posts")
    posts.find_count.should eq(1)
    client.get("/proxy")
    posts.find_count.should eq(2)
  end

  it "does not fill find when generation changed after the miss" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Find,
      phase: Alumna::RulePhase::After,
    )
    ctx.store["alumna.cache.fgen"] = 0_i64
    ctx.result = [Alumna.hash(title: "A")]
    cache.incr("alumna:fgen:/posts")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(1)
  end

  it "does not fill find when the result is not a list of hashes" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Find,
      phase: Alumna::RulePhase::After,
    )
    ctx.store["alumna.cache.fgen"] = 0_i64
    ctx.result = Alumna.hash(title: "A")
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "does not fill find when before did not store a generation" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Find,
      phase: Alumna::RulePhase::After,
    )
    ctx.result = [Alumna.hash(title: "A")]
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "treats corrupt find bytes as a miss" do
    cache = CacheKeySpy.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Find,
      phase: Alumna::RulePhase::Before,
    )
    Alumna::Testing.run_rule(rule, ctx: ctx)
    key = cache.last_get
    cache.set(key, "not-json".to_slice)
    Alumna::Testing.run_rule(rule, ctx: ctx)
    ctx.result_set?.should be_false
    cache.get(key).should be_nil
  end

  it "treats a non-array find JSON value as a miss" do
    cache = CacheKeySpy.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Find,
      phase: Alumna::RulePhase::Before,
    )
    Alumna::Testing.run_rule(rule, ctx: ctx)
    key = cache.last_get
    cache.set(key, %({"title":"A"}).to_slice)
    Alumna::Testing.run_rule(rule, ctx: ctx)
    ctx.result_set?.should be_false
    cache.get(key).should be_nil
  end

  it "treats a find array of non-objects as a miss" do
    cache = CacheKeySpy.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Find,
      phase: Alumna::RulePhase::Before,
    )
    Alumna::Testing.run_rule(rule, ctx: ctx)
    key = cache.last_get
    cache.set(key, "[1]".to_slice)
    Alumna::Testing.run_rule(rule, ctx: ctx)
    ctx.result_set?.should be_false
  end

  it "skips a listed provider on find" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Find,
      phase: Alumna::RulePhase::After,
      provider: "internal",
    )
    ctx.store["alumna.cache.fgen"] = 0_i64
    ctx.result = [Alumna.hash(title: "A")]
    Alumna::Testing.run_rule(rule, ctx: ctx)
    cache.size.should eq(0)
  end

  it "uses generation 0 when the find generation value is not an integer" do
    cache = CacheKeySpy.new
    cache.set("alumna:fgen:/posts", "nope".to_slice)
    rule = Alumna.cache(cache, ttl: 1.hour)
    svc = Alumna::MemoryAdapter.new
    svc.path = "/posts"
    ctx = Alumna::Testing.build_ctx(
      service: svc,
      method: Alumna::ServiceMethod::Find,
      phase: Alumna::RulePhase::Before,
    )
    Alumna::Testing.run_rule(rule, ctx: ctx)
    key = cache.last_get
    cache.set(key, %([{"title":"A"}]).to_slice)
    Alumna::Testing.run_rule(rule, ctx: ctx)
    ctx.result.as?(Array(Hash(String, Alumna::AnyData))).try(&.size).should eq(1)
  end

  it "caches a find with an equality filter" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    posts = CacheFindCounter.new(cache_schema)
    posts.before(rule, on: :read)
    posts.after(rule)
    app = Alumna::App.new
    app.use "/posts", posts
    client = Alumna::Testing::AppClient.new(app)
    client.post("/posts", body: %({"title":"A"}))
    client.get("/posts?title=A").json_array.size.should eq(1)
    client.get("/posts?title=A").json_array.size.should eq(1)
    posts.find_count.should eq(1)
  end

  it "includes filters sort and select in the find key" do
    cache = Alumna::MemoryCache.new
    rule = Alumna.cache(cache, ttl: 1.hour)
    posts = CacheFindCounter.new(cache_schema)
    posts.before(rule, on: :read)
    posts.after(rule)
    app = Alumna::App.new
    app.use "/posts", posts
    client = Alumna::Testing::AppClient.new(app)
    client.post("/posts", body: %({"title":"A"}))
    client.post("/posts", body: %({"title":"B"}))
    client.get("/posts?title[$in]=A,B&$sort=title:1&$select=title")
    client.get("/posts?title[$in]=A,B&$sort=title:-1&$select=title")
    posts.find_count.should eq(2)
  end
end
