require "json"

module Alumna
  module JsonHelper
    # Safely encodes Alumna's AnyData to a JSON::Builder stream
    def self.encode(val : AnyData, builder : JSON::Builder) : Nil
      case val
      when String then builder.scalar(val)
      when Int    then builder.scalar(val) # no .to_i64 needed
      when Float  then builder.scalar(val) # no .to_f64 needed
      when Bool   then builder.scalar(val)
      when Nil    then builder.null
      when Time
        builder.string { |io| Time::Format::RFC_3339.format(val, io, fraction_digits: 0) }
      when Bytes
        builder.array { val.each { |byte| builder.scalar(byte) } }
      when Array
        builder.array { val.each { |item| encode(item, builder) } }
      when Hash
        builder.object do
          val.each { |k, v| builder.field(k.to_s) { encode(v, builder) } }
        end
      else
        builder.null
      end
    end

    # Safely decodes a JSON::PullParser stream directly into Alumna's AnyData union
    def self.decode(pull : JSON::PullParser) : AnyData
      case pull.kind
      when .null?   then pull.read_null
      when .bool?   then pull.read_bool
      when .int?    then pull.read_int
      when .float?  then pull.read_float
      when .string? then pull.read_string
      when .begin_array?
        ary = [] of AnyData
        pull.read_array { ary << decode(pull) }
        ary
      when .begin_object?
        hash = {} of String => AnyData
        pull.read_object { |key| hash[key] = decode(pull) }
        hash
      else
        # Prevent crashing on unexpected/malformed internal tokens
        pull.skip
        nil
      end
    end

    # Convenience method for Adapters to serialize AnyData to a String
    def self.to_string(val : AnyData) : String
      String.build do |io|
        JSON.build(io) { |builder| encode(val, builder) }
      end
    end

    # Convenience method for Adapters to deserialize a JSON string into AnyData
    def self.from_string(json_str : String) : AnyData
      pull = JSON::PullParser.new(json_str)
      decode(pull)
    end
  end
end
