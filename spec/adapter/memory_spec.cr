require "../spec_helper"
require "../../src/testing"

private def memory_adapter_suite_schema
  Alumna::Schema.new(strict: false)
    .str("role").str("name").str("grade").str("status")
    .int("age").float("rating").bool("active").time("created")
    .hash("user") { |u| u.str("name"); u.int("age") }
    .array("tags", of: :str)
    .int("score").float("price").int("order_index").str("category").bool("is_published")
    .str("title", required: false).str("sequence", required: false)
    .str("first_name", required: false).str("last_name", required: false)
    .int("view_count", required: false).any("metadata", nullable: true, required: false)
end

Alumna::Testing::AdapterSuite.run("Alumna::MemoryAdapter") do
  Alumna::MemoryAdapter.new(memory_adapter_suite_schema)
end

Alumna::Testing::AdapterSuite.run("Alumna::MemoryAdapter (opaque ids)", expect_incremental_ids: false) do
  Alumna::MemoryAdapter.new(memory_adapter_suite_schema)
end

# Spec-only store. Production MemoryAdapter stays SQLite-like (D32).
# This compiles and runs AdapterSuite mixed_sort: :bson in backend coverage.
private class BsonMixedSortMemoryAdapter < Alumna::MemoryAdapter
  def find(ctx : Alumna::RuleContext) : Array(Hash(String, Alumna::AnyData)) | Alumna::ServiceError
    result = super
    return result if result.is_a?(Alumna::ServiceError)

    sort = ctx.query.sort
    return result unless sort

    has_metadata = false
    sort.each { |field, _dir| has_metadata = true if field == "metadata" }
    return result unless has_metadata

    result.sort! do |a, b|
      acc = 0
      sort.each do |field, dir|
        next unless acc == 0
        acc = compare_bson_mixed(a.dig_any?(field), b.dig_any?(field)) * dir
      end
      acc
    end
    result
  end

  private def compare_bson_mixed(a : Alumna::AnyData?, b : Alumna::AnyData?) : Int32
    compare_rank(min_element(a), min_element(b))
  end

  # MongoDB ascending: a non-array is compared to the least element of an array.
  private def min_element(v : Alumna::AnyData?) : Alumna::AnyData?
    return v unless v.is_a?(Array(Alumna::AnyData))
    return v if v.empty?

    min = v[0]
    v.each do |el|
      if compare_rank(min_element(el), min_element(min)) < 0
        min = el
      end
    end
    min_element(min)
  end

  private def compare_rank(a : Alumna::AnyData?, b : Alumna::AnyData?) : Int32
    wa = rank(a)
    wb = rank(b)
    return wa <=> wb if wa != wb
    if a.is_a?(Int64 | Float64) && b.is_a?(Int64 | Float64)
      return (a <=> b) || 0
    end
    if a.is_a?(String) && b.is_a?(String)
      return a <=> b
    end
    0
  end

  private def rank(v : Alumna::AnyData?) : Int32
    case v
    when Nil                  then 0
    when Int64, Float64, Bool then 1
    else                           2
    end
  end
end

Alumna::Testing::AdapterSuite.run("Alumna::MemoryAdapter (bson mixed sort)", mixed_sort: :bson) do
  BsonMixedSortMemoryAdapter.new(memory_adapter_suite_schema)
end

describe "MemoryAdapter Unique Constraints" do
  schema = Alumna::Schema.new
    .str("email", unique: true)
    .str("username", unique: true)
    .str("bio", required: false)

  it "enforces uniqueness on create" do
    adapter = Alumna::MemoryAdapter.new(schema)

    # 1. First insert should succeed
    ctx1 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"email" => "alice@a.com", "username" => "alice"} of String => Alumna::AnyData)
    res1 = adapter.create(ctx1)
    res1.should be_a(Hash(String, Alumna::AnyData))

    # 2. Duplicate email should fail
    ctx2 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"email" => "alice@a.com", "username" => "bob"} of String => Alumna::AnyData)
    res2 = adapter.create(ctx2)
    res2.should be_a(Alumna::ServiceError)
    res2.as(Alumna::ServiceError).status.should eq(422)
    res2.as(Alumna::ServiceError).details["email"].should eq("already exists")

    # 3. Duplicate username should fail
    ctx3 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"email" => "bob@a.com", "username" => "alice"} of String => Alumna::AnyData)
    res3 = adapter.create(ctx3)
    res3.as(Alumna::ServiceError).details["username"].should eq("already exists")
  end

  it "enforces uniqueness on update and patch, safely skipping its own ID" do
    adapter = Alumna::MemoryAdapter.new(schema)

    # Setup
    c_ctx1 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"email" => "alice@a.com", "username" => "alice"} of String => Alumna::AnyData)
    c_ctx2 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"email" => "bob@a.com", "username" => "bob"} of String => Alumna::AnyData)
    id1 = adapter.create(c_ctx1).as(Hash(String, Alumna::AnyData))["id"].as(String)
    id2 = adapter.create(c_ctx2).as(Hash(String, Alumna::AnyData))["id"].as(String)

    # 1. Patching to an existing email (owned by someone else) should fail
    p_ctx1 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: id2, data: {"email" => "alice@a.com"} of String => Alumna::AnyData)
    res1 = adapter.patch(p_ctx1)
    res1.should be_a(Alumna::ServiceError)
    res1.as(Alumna::ServiceError).status.should eq(422)

    # 2. Patching a record WITHOUT changing its unique fields (or updating to the same value) MUST succeed
    p_ctx2 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: id1, data: {"email" => "alice@a.com", "bio" => "new bio"} of String => Alumna::AnyData)
    res2 = adapter.patch(p_ctx2)
    res2.should be_a(Hash(String, Alumna::AnyData))
    res2.as(Hash(String, Alumna::AnyData))["bio"].should eq("new bio")
  end
end

private def insert_sequences(adapter : Alumna::Service, n : Int32)
  n.times do |i|
    Alumna::Testing::AdapterSuiteHelpers.insert(adapter, Alumna.hash(sequence: i.to_s))
  end
end

describe "MemoryAdapter query limit caps" do
  it "returns all matching rows when App caps are nil and $limit is omitted" do
    app = Alumna::App.new
    adapter = Alumna::MemoryAdapter.new
    insert_sequences(adapter, 5)
    ctx = Alumna::Testing.build_ctx(app: app, service: adapter, method: Alumna::ServiceMethod::Find)
    results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
    results.size.should eq(5)
  end

  it "returns remaining rows for $skip without $limit when caps are unset" do
    app = Alumna::App.new
    adapter = Alumna::MemoryAdapter.new
    insert_sequences(adapter, 5)
    ctx = Alumna::Testing.build_ctx(
      app: app,
      service: adapter,
      method: Alumna::ServiceMethod::Find,
      params: {"$skip" => "2"}
    )
    results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
    results.size.should eq(3)
    results.map(&.["sequence"]).should eq(["2", "3", "4"])
  end

  it "applies default_query_limit when the client omits $limit" do
    app = Alumna::App.new
    app.default_query_limit = 2
    adapter = Alumna::MemoryAdapter.new
    insert_sequences(adapter, 5)
    ctx = Alumna::Testing.build_ctx(app: app, service: adapter, method: Alumna::ServiceMethod::Find)
    adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).size.should eq(2)
  end

  it "clamps a client $limit that is above max_query_limit" do
    app = Alumna::App.new
    app.max_query_limit = 2
    adapter = Alumna::MemoryAdapter.new
    insert_sequences(adapter, 5)
    ctx = Alumna::Testing.build_ctx(
      app: app,
      service: adapter,
      method: Alumna::ServiceMethod::Find,
      params: {"$limit" => "10"}
    )
    adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).size.should eq(2)
  end

  it "uses the tighter of default_query_limit and max_query_limit" do
    app = Alumna::App.new
    app.default_query_limit = 10
    app.max_query_limit = 2
    adapter = Alumna::MemoryAdapter.new
    insert_sequences(adapter, 5)
    ctx = Alumna::Testing.build_ctx(app: app, service: adapter, method: Alumna::ServiceMethod::Find)
    adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).size.should eq(2)
  end

  it "does not invent a limit when only max_query_limit is set" do
    app = Alumna::App.new
    app.max_query_limit = 2
    adapter = Alumna::MemoryAdapter.new
    insert_sequences(adapter, 5)
    ctx = Alumna::Testing.build_ctx(app: app, service: adapter, method: Alumna::ServiceMethod::Find)
    adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).size.should eq(5)
  end

  it "returns 400 for invalid $limit and $skip" do
    app = Alumna::App.new
    adapter = Alumna::MemoryAdapter.new
    limit_ctx = Alumna::Testing.build_ctx(
      app: app,
      service: adapter,
      method: Alumna::ServiceMethod::Find,
      params: {"$limit" => "abc"}
    )
    limit_err = adapter.find(limit_ctx)
    limit_err.should be_a(Alumna::ServiceError)
    limit_err.as(Alumna::ServiceError).status.should eq(400)

    skip_ctx = Alumna::Testing.build_ctx(
      app: app,
      service: adapter,
      method: Alumna::ServiceMethod::Find,
      params: {"$skip" => "-1"}
    )
    skip_err = adapter.find(skip_ctx)
    skip_err.should be_a(Alumna::ServiceError)
    skip_err.as(Alumna::ServiceError).status.should eq(400)
  end
end
