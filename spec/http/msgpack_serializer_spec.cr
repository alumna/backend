require "../spec_helper"
require "msgpack"

describe Alumna::Http::MsgpackSerializer do
  it "returns application/msgpack" do
    serializer = Alumna::Http::MsgpackSerializer.new
    serializer.content_type.should eq("application/msgpack")
  end

  it "encodes and decodes all types successfully, including BytesT" do
    serializer = Alumna::Http::MsgpackSerializer.new
    io = IO::Memory.new

    data = {
      "str"   => "hello",
      "int"   => 42_i64,
      "float" => 3.14_f64,
      "bool"  => true,
      "null"  => nil,
      "ary"   => ["a", "b"] of Alumna::AnyData,
      "hash"  => {"k" => "v"} of String => Alumna::AnyData,
      "time"  => Time.utc(2024, 1, 1),
      "bytes" => Bytes[0x01, 0x02],
    } of String => Alumna::AnyData

    serializer.encode(data, io)
    io.rewind

    decoded = serializer.decode(io).as(Hash(String, Alumna::AnyData))

    decoded["str"].should eq("hello")
    decoded["int"].should eq(42_i64)
    decoded["float"].should eq(3.14_f64)
    decoded["bool"].should eq(true)
    decoded["null"].should be_nil
    decoded["ary"].as(Array(Alumna::AnyData)).should eq(["a", "b"])
    decoded["hash"].as(Hash(String, Alumna::AnyData)).should eq({"k" => "v"})

    # Time encodes natively via the shard as an ISO8601 string
    decoded["time"].should eq("2024-01-01T00:00:00Z")

    # Bytes decode natively and perfectly hit the BytesT branch!
    decoded["bytes"].should eq(Bytes[0x01, 0x02])
  end

  it "handles unexpected MessagePack extensions gracefully" do
    serializer = Alumna::Http::MsgpackSerializer.new

    # Manually pack an ExtT (MessagePack extension type) which we explicitly reject
    packer = MessagePack::Packer.new
    packer.write_hash_start(1)
    packer.write("bad_token")
    packer.write_ext(1_i8, Bytes[0xFF])

    io = IO::Memory.new(packer.to_slice)
    res = serializer.decode(io)

    # Hits the 'raise MessagePack::TypeCastError' fallback
    res.should be_a(Alumna::ServiceError)
    err = res.as(Alumna::ServiceError)
    err.status.should eq(400)
    err.message.should eq("Malformed MessagePack")
  end
end
