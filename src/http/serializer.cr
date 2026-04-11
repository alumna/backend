module Alumna
  module Http
    abstract class Serializer
      abstract def content_type : String
      abstract def encode(data : Hash(String, AnyData), io : IO) : Nil
      abstract def encode(data : Array(Hash(String, AnyData)), io : IO) : Nil
      abstract def decode(io : IO) : Hash(String, AnyData)
    end
  end
end
