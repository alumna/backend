require "uuid"

Alumna::Formats.register("uuid", "must be a valid UUID") do |v|
  !!UUID.parse?(v)
end
