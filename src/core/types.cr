module Alumna
  struct AnyData
    alias Raw = Nil | Bool | Int64 | Float64 | String | Array(AnyData) | Hash(String, AnyData)

    getter raw : Raw

    def initialize(@raw : Raw)
    end

    def to_json(json : JSON::Builder) : Nil
      raw.to_json(json)
    end
  end

  alias ServiceResult = Hash(String, AnyData) | Array(Hash(String, AnyData)) | Nil
end
