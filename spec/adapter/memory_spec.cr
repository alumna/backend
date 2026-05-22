require "../spec_helper"
require "../../src/testing"

# This single line runs ~50+ assertions covering all expected behavior
# of an Alumna adapter, guaranteeing MemoryAdapter is fully compliant!
Alumna::Testing::AdapterSuite.run("Alumna::MemoryAdapter") do
  Alumna::MemoryAdapter.new(
    Alumna::Schema.new(strict: false)
      .str("role").str("name").str("letter").str("status")
      .int("age").float("rating").bool("active").time("created")
      .hash("user") { |u| u.str("name"); u.int("age") }
      .array("tags", of: :str)
      .int("score").float("val").int("pos").str("str").bool("flag")
  )
end
