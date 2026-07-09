require "../spec_helper"
require "../../src/testing"

Alumna::Testing::AdapterSuite.run("Alumna::MemoryAdapter") do
  Alumna::MemoryAdapter.new(
    Alumna::Schema.new(strict: false)
      .str("role").str("name").str("grade").str("status")
      .int("age").float("rating").bool("active").time("created")
      .hash("user") { |u| u.str("name"); u.int("age") }
      .array("tags", of: :str)
      .int("score").float("price").int("order_index").str("category").bool("is_published")
      .str("title", required: false).str("sequence", required: false)
      .str("first_name", required: false).str("last_name", required: false)
      .int("view_count", required: false).any("metadata", nullable: true, required: false)
  )
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
