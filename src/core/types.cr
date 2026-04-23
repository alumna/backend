# src/core/types.cr
module Alumna
  alias AnyData = Nil | Bool | Int64 | Float64 | String | Array(AnyData) | Hash(String, AnyData)
end
