require "../spec_helper"
require "../../src/testing"

# This single line runs ~50+ assertions covering all expected behavior
# of an Alumna adapter, guaranteeing MemoryAdapter is fully compliant!
Alumna::Testing::AdapterSuite.run("Alumna::MemoryAdapter") do
  Alumna::MemoryAdapter.new
end
