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
        result = decode_value(unpacker)
        unless result.is_a?(Hash(String, AnyData))
          return ServiceError.new("Request body must be a MessagePack map", 400)
        end
        result
      rescue MessagePack::UnpackError | MessagePack::TypeCastError | MessagePack::EofError | OverflowError
        ServiceError.new("Malformed MessagePack", 400)
      end

      private def decode_value(unpacker : MessagePack::Unpacker) : AnyData
        case token = unpacker.current_token
        when MessagePack::Token::NullT
          unpacker.finish_token!
          nil
        when MessagePack::Token::BoolT
          unpacker.finish_token!
          token.value
        when MessagePack::Token::IntT
          unpacker.finish_token!
          token.value.to_i64
        when MessagePack::Token::FloatT
          unpacker.finish_token!
          token.value
        when MessagePack::Token::StringT
          unpacker.finish_token!
          token.value
        when MessagePack::Token::BytesT
          unpacker.finish_token!
          token.value
        when MessagePack::Token::ArrayT
          # Cap pre-allocation to prevent OOM DoS from maliciously crafted headers
          cap = Math.min(token.size, 65536).to_i
          ary = Array(AnyData).new(initial_capacity: cap)
          unpacker.consume_array { ary << decode_value(unpacker) }
          ary
        when MessagePack::Token::HashT
          cap = Math.min(token.size, 65536).to_i
          hash = Hash(String, AnyData).new(initial_capacity: cap)
          unpacker.consume_table { |key| hash[key] = decode_value(unpacker) }
          hash
        else
          raise MessagePack::TypeCastError.new(
            "Unexpected token: #{MessagePack::Token.to_s(token)}", token.byte_number
          )
        end
      end
    end
  end
end
