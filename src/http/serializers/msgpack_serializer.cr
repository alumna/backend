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
        peeked = io.peek
        return {} of String => AnyData if peeked.nil? || peeked.empty?

        unpacker = MessagePack::IOUnpacker.new(io)
        result = Hash(String, AnyData).new
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
        case raw = value.raw
        when Nil     then nil
        when Bool    then raw
        when Int64   then raw
        when Float64 then raw
        when String  then raw
        when Array   then raw.map { |v| json_any_to_msgpack(v) }.as(MessagePack::Type)
        when Hash
          result = Hash(MessagePack::Type, MessagePack::Type).new
          raw.each do |k, v|
            result[k.to_s.as(MessagePack::Type)] = json_any_to_msgpack(v)
          end
          result.as(MessagePack::Type)
        else nil
        end
      end

      private def from_msgpack_type(value : MessagePack::Type) : AnyData
        case value
        when Nil                                                      then AnyData.new(nil)
        when Bool                                                     then AnyData.new(value)
        when Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64 then AnyData.new(value.to_i64)
        when Float32, Float64                                         then AnyData.new(value.to_f64)
        when String                                                   then AnyData.new(value)
        when Array                                                    then AnyData.new(value.map { |v| from_msgpack_type(v) })
        when Hash                                                     then AnyData.new(value.transform_keys(&.to_s).transform_values { |v| from_msgpack_type(v) })
        else                                                               AnyData.new(nil)
        end
      end
    end
  end
end
