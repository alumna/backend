require "../spec_helper"

describe Alumna::MemoryCache do
  it "round-trips bytes" do
    cache = Alumna::MemoryCache.new
    cache.set("k", "hello".to_slice)
    cache.get("k").should eq("hello".to_slice)
  end

  it "returns nil for an unknown key" do
    cache = Alumna::MemoryCache.new
    cache.get("missing").should be_nil
  end

  it "returns nil after delete" do
    cache = Alumna::MemoryCache.new
    cache.set("k", "v".to_slice)
    cache.delete("k")
    cache.get("k").should be_nil
  end

  it "expires on get after the ttl" do
    cache = Alumna::MemoryCache.new
    cache.set("k", "v".to_slice, 1.nanosecond)
    sleep 1.milliseconds
    cache.get("k").should be_nil
    cache.size.should eq(0)
  end

  it "keeps an entry with no ttl" do
    cache = Alumna::MemoryCache.new
    cache.set("k", "v".to_slice)
    sleep 1.milliseconds
    cache.get("k").should eq("v".to_slice)
  end

  it "overwrites a key" do
    cache = Alumna::MemoryCache.new
    cache.set("k", "a".to_slice)
    cache.set("k", "b".to_slice)
    cache.get("k").should eq("b".to_slice)
  end

  it "does not alias the stored slice with the caller slice" do
    cache = Alumna::MemoryCache.new
    buf = Bytes.new(1, 1_u8)
    cache.set("k", buf)
    buf[0] = 2_u8
    cache.get("k").should eq(Bytes.new(1, 1_u8))
  end

  it "does not alias the stored slice with the returned slice" do
    cache = Alumna::MemoryCache.new
    cache.set("k", Bytes.new(1, 1_u8))
    got = cache.get("k")
    if got
      got[0] = 9_u8
    end
    cache.get("k").should eq(Bytes.new(1, 1_u8))
  end

  it "prunes expired entries" do
    cache = Alumna::MemoryCache.new(cleanup_every: 1000)
    cache.set("a", "1".to_slice, 1.nanosecond)
    cache.set("b", "2".to_slice, 1.nanosecond)
    cache.size.should eq(2)
    sleep 1.milliseconds
    cache.prune_expired
    cache.size.should eq(0)
  end

  it "does not prune entries with no ttl" do
    cache = Alumna::MemoryCache.new
    cache.set("keep", "v".to_slice)
    cache.set("gone", "v".to_slice, 1.nanosecond)
    sleep 1.milliseconds
    cache.prune_expired
    cache.size.should eq(1)
    cache.get("keep").should eq("v".to_slice)
  end

  it "prunes during amortized cleanup" do
    cache = Alumna::MemoryCache.new(cleanup_every: 2)
    cache.set("a", "1".to_slice, 1.nanosecond)
    sleep 1.milliseconds
    cache.set("b", "2".to_slice)
    cache.size.should eq(1)
  end

  it "rejects a non-positive ttl on set" do
    cache = Alumna::MemoryCache.new
    expect_raises(ArgumentError, "cache ttl must be > 0") do
      cache.set("k", "v".to_slice, Time::Span.zero)
    end
  end

  it "rejects cleanup_every < 1" do
    expect_raises(ArgumentError, "cleanup_every must be >= 1") do
      Alumna::MemoryCache.new(cleanup_every: 0)
    end
  end

  it "increments a missing key to 1" do
    cache = Alumna::MemoryCache.new
    cache.incr("n").should eq(1)
    cache.incr("n").should eq(2)
    cache.get("n").should eq("2".to_slice)
  end

  it "treats a non-integer value as 0 then adds 1" do
    cache = Alumna::MemoryCache.new
    cache.set("n", "nope".to_slice)
    cache.incr("n").should eq(1)
  end

  it "treats an expired value as missing on incr" do
    cache = Alumna::MemoryCache.new
    cache.set("n", "9".to_slice, 1.nanosecond)
    sleep 1.milliseconds
    cache.incr("n").should eq(1)
  end

  it "does not expire an incr counter" do
    cache = Alumna::MemoryCache.new
    cache.incr("n")
    sleep 1.milliseconds
    cache.get("n").should eq("1".to_slice)
  end

  it "set_nx writes when the key is missing" do
    cache = Alumna::MemoryCache.new
    cache.set_nx("k", "a".to_slice).should be_true
    cache.get("k").should eq("a".to_slice)
  end

  it "set_nx does not overwrite an existing key" do
    cache = Alumna::MemoryCache.new
    cache.set("k", "a".to_slice)
    cache.set_nx("k", "b".to_slice).should be_false
    cache.get("k").should eq("a".to_slice)
  end

  it "set_nx writes when the existing key is expired" do
    cache = Alumna::MemoryCache.new
    cache.set("k", "a".to_slice, 1.nanosecond)
    sleep 1.milliseconds
    cache.set_nx("k", "b".to_slice).should be_true
    cache.get("k").should eq("b".to_slice)
  end

  it "rejects a non-positive ttl on set_nx" do
    cache = Alumna::MemoryCache.new
    expect_raises(ArgumentError, "cache ttl must be > 0") do
      cache.set_nx("k", "v".to_slice, Time::Span.zero)
    end
  end
end
