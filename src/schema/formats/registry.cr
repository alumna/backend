module Alumna
  module Formats
    alias Validator = Proc(String, Bool)

    record Entry, validator : Validator, message : String

    @@registry = {} of String => Entry

    def self.register(name : String | Symbol, message : String, &block : String -> Bool)
      @@registry[name.to_s] = Entry.new(block, message)
    end

    def self.fetch(name : String) : Entry?
      @@registry[name]?
    end
  end
end
