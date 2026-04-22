require "msgpack"

module Alumna
  module Http
    class MsgpackSerializer < Serializer
      def content_type : String
        "application/msgpack"
      end

      def encode(data : Hash(String, AnyData), io : IO) : Nil
        to_msgpack_type(data).to_msgpack(io)
      end

      def encode(data : Array(Hash(String, AnyData)), io : IO) : Nil
        data.map { |h| to_msgpack_type(h) }.to_msgpack(io)
      end

      def decode(io : IO) : Hash(String, AnyData)
        unpacker = MessagePack::IOUnpacker.new(io)
        result = {} of String => AnyData
        unpacker.consume_table do |key|
          result[key] = from_msgpack_type(unpacker.read_value)
        end
        result
      rescue MessagePack::UnpackError | MessagePack::TypeCastError | MessagePack::EofError
        raise ServiceError.new("Malformed MessagePack", 400)
      end

      private def to_msgpack_type(hash : Hash(String, AnyData)) : Hash(String, MessagePack::Type)
        result = Hash(String, MessagePack::Type).new
        hash.each do |k, v|
          result[k] = json_any_to_msgpack(v)
        end
        result
      end

      private def json_any_to_msgpack(value : AnyData) : MessagePack::Type
        case value.raw
        when Nil, Bool, Int64, Float64, String
          value.raw.as(MessagePack::Type)
        when Array(AnyData)
          value.raw.as(Array(AnyData)).map { |v| json_any_to_msgpack(v) }.as(MessagePack::Type)
        when Hash(String, AnyData)
          value.raw.as(Hash(String, AnyData))
            .transform_keys { |k| k.as(MessagePack::Type) }
            .transform_values { |v| json_any_to_msgpack(v) }
            .as(MessagePack::Type)
        else
          nil.as(MessagePack::Type)
        end
      end

      private def from_msgpack_type(value : MessagePack::Type) : AnyData
        case value
        when Nil    then AnyData.new(nil)
        when Bool   then AnyData.new(value)
        when Int    then AnyData.new(value.to_i64)
        when Float  then AnyData.new(value.to_f64)
        when String then AnyData.new(value)
        when Array  then AnyData.new(value.map { |v| from_msgpack_type(v) })
        when Hash   then AnyData.new(value.transform_keys(&.to_s).transform_values { |v| from_msgpack_type(v) })
        else             AnyData.new(nil)
        end
      end
    end
  end
end
