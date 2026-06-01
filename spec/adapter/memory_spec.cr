require "../spec_helper"
require "../../src/testing"

Alumna::Testing::AdapterSuite.run("Alumna::MemoryAdapter") do
  Alumna::MemoryAdapter.new(
    Alumna::Schema.new(strict: false)
      .str("role").str("name").str("grade").str("status")
      .int("age").float("rating").bool("active").time("created")
      .hash("user") { |u| u.str("name"); u.int("age") }
      .array("tags", of: :str)
      .int("score").float("price").int("order_index").str("category").bool("is_published")
      .str("title", required: false).str("sequence", required: false)
      .str("first_name", required: false).str("last_name", required: false)
      .int("view_count", required: false).nullable("metadata", required: false)
  )
end
