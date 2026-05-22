# src/core/types.cr
module Alumna
  # An explicit marker module.
  # Include this in your custom classes/structs (like `User`)
  # to allow them to be safely saved and retrieved from `ctx.store`.
  module Storeable; end

  alias AnyData = Nil | Bool | Int64 | Float64 | String | Time | Bytes | Array(AnyData) | Hash(String, AnyData)

  # A broader type for the context store, allowing developers to share
  # arbitrary marked objects across rules alongside standard primitives.
  alias StoreType = AnyData | Storeable
end
