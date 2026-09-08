require "../../../spec_helper"

describe Alumna::MemorySessionStore do
  it "round-trips data" do
    store = Alumna::MemorySessionStore.new(ttl: 1.hour)
    id = store.new_id
    store.set(id, Alumna.hash(user_id: "1"))
    got = store.get(id)
    got.should eq(Alumna.hash(user_id: "1"))
  end

  it "returns nil for an unknown id" do
    store = Alumna::MemorySessionStore.new
    store.get("missing").should be_nil
  end

  it "returns nil after delete" do
    store = Alumna::MemorySessionStore.new
    id = store.new_id
    store.set(id, Alumna.hash(k: "v"))
    store.delete(id)
    store.get(id).should be_nil
  end

  it "expires on get after the ttl" do
    store = Alumna::MemorySessionStore.new(ttl: 1.nanosecond)
    id = store.new_id
    store.set(id, Alumna.hash(k: "v"))
    sleep 1.milliseconds
    store.get(id).should be_nil
    store.size.should eq(0)
  end

  it "honors a per-set ttl" do
    store = Alumna::MemorySessionStore.new(ttl: 1.hour)
    id = store.new_id
    store.set(id, Alumna.hash(k: "v"), 1.nanosecond)
    sleep 1.milliseconds
    store.get(id).should be_nil
  end

  it "does not alias the stored hash with the caller hash" do
    store = Alumna::MemorySessionStore.new
    id = store.new_id
    data = Alumna.hash(k: "v")
    store.set(id, data)
    data["k"] = "mutated"
    store.get(id).try(&.["k"]).should eq("v")
  end

  it "does not alias the stored hash with the returned hash" do
    store = Alumna::MemorySessionStore.new
    id = store.new_id
    store.set(id, Alumna.hash(k: "v"))
    got = store.get(id)
    if got
      got["k"] = "mutated"
    end
    store.get(id).try(&.["k"]).should eq("v")
  end

  it "prunes expired entries" do
    store = Alumna::MemorySessionStore.new(ttl: 1.nanosecond, cleanup_every: 1000)
    store.set("a", Alumna.hash(n: "1"))
    store.set("b", Alumna.hash(n: "2"))
    store.size.should eq(2)
    sleep 1.milliseconds
    store.prune_expired
    store.size.should eq(0)
  end

  it "prunes during amortized cleanup" do
    store = Alumna::MemorySessionStore.new(ttl: 1.nanosecond, cleanup_every: 2)
    store.set("a", Alumna.hash(n: "1"))
    sleep 1.milliseconds
    store.set("b", Alumna.hash(n: "2"))
    store.size.should eq(1)
  end

  it "rejects a non-positive ttl at boot" do
    expect_raises(ArgumentError, "session ttl must be > 0") do
      Alumna::MemorySessionStore.new(ttl: Time::Span.zero)
    end
  end

  it "rejects a non-positive ttl on set" do
    store = Alumna::MemorySessionStore.new
    expect_raises(ArgumentError, "session ttl must be > 0") do
      store.set("a", Alumna.hash(k: "v"), Time::Span.zero)
    end
  end

  it "rejects cleanup_every < 1" do
    expect_raises(ArgumentError, "cleanup_every must be >= 1") do
      Alumna::MemorySessionStore.new(cleanup_every: 0)
    end
  end

  it "creates unique ids" do
    store = Alumna::MemorySessionStore.new
    store.new_id.should_not eq(store.new_id)
    store.new_id.size.should be > 0
  end
end
