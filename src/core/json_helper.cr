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

    # Writes *val* as JSON into *io*. No `JSON::Builder` and no extra String.
    def self.write(io : IO, val : AnyData) : Nil
      case val
      when String then write_string(io, val)
      when Int    then io << val
      when Float
        if val.nan?
          raise JSON::Error.new("NaN not allowed in JSON")
        elsif val.infinite?
          raise JSON::Error.new("Infinity not allowed in JSON")
        end
        io << val
      when Bool then io << (val ? "true" : "false")
      when Nil  then io << "null"
      when Time
        io << '"'
        Time::Format::RFC_3339.format(val, io, fraction_digits: 0)
        io << '"'
      when Bytes
        io << '['
        index = 0
        while index < val.size
          io << ',' if index > 0
          io << val[index]
          index &+= 1
        end
        io << ']'
      when Array
        io << '['
        index = 0
        while index < val.size
          io << ',' if index > 0
          write(io, val[index])
          index &+= 1
        end
        io << ']'
      when Hash
        io << '{'
        first = true
        val.each do |key, item|
          if first
            first = false
          else
            io << ','
          end
          write_string(io, key.to_s)
          io << ':'
          write(io, item)
        end
        io << '}'
      else
        io << "null"
      end
    end

    # Writes a JSON string. Matches `JSON::Builder` escaping.
    def self.write_string(io : IO, value : String) : Nil
      io << '"'
      bytes = value.to_slice
      start = 0
      index = 0
      while index < bytes.size
        byte = bytes[index]
        if byte >= 0x20 && byte != 0x7f && byte != 34 && byte != 92
          index &+= 1
          next
        end
        io.write(bytes[start, index - start]) if index > start
        case byte
        when 92_u8 then io << "\\\\"
        when 34_u8 then io << "\\\""
        when  8_u8 then io << "\\b"
        when 12_u8 then io << "\\f"
        when 10_u8 then io << "\\n"
        when 13_u8 then io << "\\r"
        when  9_u8 then io << "\\t"
        else
          io << "\\u00"
          io << '0' if byte < 0x10
          byte.to_s(io, 16)
        end
        index &+= 1
        start = index
      end
      io.write(bytes[start, bytes.size - start]) if start < bytes.size
      io << '"'
    end

    # Convenience method for Adapters to serialize AnyData to a String
    def self.to_string(val : AnyData) : String
      String.build { |io| write(io, val) }
    end

    # Convenience method for Adapters to deserialize a JSON string into AnyData
    def self.from_string(json_str : String) : AnyData
      pull = JSON::PullParser.new(json_str)
      decode(pull)
    end
  end
end
