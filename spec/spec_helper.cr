require "spec"
require "../src/alumna"

def must_sid(result : String | Alumna::StoreError) : String
  if result.is_a?(Alumna::StoreError)
    fail result.message
  end
  result
end
