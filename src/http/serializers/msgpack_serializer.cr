require "msgpack"

module Alumna
  module Http
    class MsgpackSerializer < Serializer
      def content_type : String
        "application/msgpack"
      end

      def encode(data : Hash(String, AnyData), io : IO) : Nil
        data.to_msgpack(io)
      end

      def encode(data : Array(Hash(String, AnyData)), io : IO) : Nil
        data.to_msgpack(io)
      end

      def decode(io : IO) : Hash(String, AnyData) | ServiceError
        unpacker = MessagePack::IOUnpacker.new(io)
        result = {} of String => AnyData
        unpacker.consume_table do |key|
          result[key] = normalize(unpacker.read_value)
        end
        result
      rescue MessagePack::UnpackError | MessagePack::TypeCastError | MessagePack::EofError
        ServiceError.new("Malformed MessagePack", 400)
      end

      private def normalize(value : MessagePack::Type) : AnyData
        case value
        when Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64
          value.to_i64
        when Float32
          value.to_f64
        when Float64, String, Bool, Nil
          value
        when Array
          value.map { |v| normalize(v) }
        when Hash
          value.each_with_object({} of String => AnyData) do |(k, v), memo|
            memo[k.to_s] = normalize(v)
          end
        else
          nil
        end
      end
    end
  end
end
