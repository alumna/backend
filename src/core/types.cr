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

  # DX Helper: Auto-cast common types to their AnyData equivalents
  def self.to_any(v : Int8 | Int16 | Int32 | UInt8 | UInt16 | UInt32 | UInt64) : AnyData
    v.to_i64
  end

  def self.to_any(v : Float32) : AnyData
    v.to_f64
  end

  def self.to_any(v : AnyData) : AnyData
    v
  end

  # Helper macro to cleanly instantiate a Hash(String, AnyData)
  # without the `of String => AnyData` generic friction.
  macro hash(**named_args)
      {
        {% for key, value in named_args %}
          {{key.id.stringify}} => Alumna.to_any({{value}}).as(Alumna::AnyData),
        {% end %}
      } of String => Alumna::AnyData
    end
end

class Array(T)
  # Converts any array into an Alumna Array(AnyData) with minimal syntax,
  # gracefully auto-casting Int32/Float32 to Int64/Float64.
  def to_any : Array(Alumna::AnyData)
    self.map { |v| Alumna.to_any(v).as(Alumna::AnyData) }
  end
end

class Hash(K, V)
  # Safe deep fetching for nested structures (e.g. AnyData).
  def dig_any?(path : String) : V?
    {% if K == String %}
      return self[path]? if self.has_key?(path)

      current = self
      start = 0
      val = nil

      loop do
        dot = path.index('.', start)
        part = dot ? path[start...dot] : path[start..]

        if current.is_a?(Hash(String, V))
          val = current.as(Hash(String, V))[part]?
        else
          return nil
        end

        break unless dot
        return nil if val.nil?
        start = dot + 1
        current = val
      end

      val.as?(V)
      # LCOV_EXCL_START - kcov misses methods that compile to a pure nil return
    {% else %} nil {% end %}
    # LCOV_EXCL_STOP
  end

  # Strict deep fetching that raises KeyError if the path is missing.
  def dig_any(path : String) : V
    val = dig_any?(path)
    raise KeyError.new("Missing hash path: #{path.inspect}") if val.nil?
    val
  end

  # Typed accessors generated at compile time
  {% for type, suffix in {String => "str", Int64 => "int", Float64 => "float", Bool => "bool", Time => "time", Bytes => "bytes"} %}
    def dig_{{suffix.id}}?(path : String) : {{type}}?
      dig_any?(path).as?({{type}})
    end

    def dig_{{suffix.id}}(path : String) : {{type}}
      val = dig_any?(path)
      raise KeyError.new("Missing hash path: #{path.inspect}") if val.nil?
      val.as({{type}})
    end
  {% end %}
end
