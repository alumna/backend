require "set"

module Alumna
  module Http
    struct HeadersView
      include Enumerable({String, String})
      @overlay : Hash(String, String)?

      def initialize(@src : HTTP::Headers)
        @overlay = nil
      end

      def [](key : String) : String?
        k = key.downcase
        if ov = @overlay
          return ov[k] if ov.has_key?(k)
        end
        @src[k]?
      end

      def []?(key : String) : String?
        self[key]
      end

      def []=(key : String, value : String) : String
        (@overlay ||= {} of String => String)[key.downcase] = value
      end

      def each(& : {String, String} ->)
        seen = Set(String).new
        if ov = @overlay
          ov.each { |k, v| seen << k; yield({k, v}) }
        end
        @src.each do |k, vs|
          lk = k.downcase
          next if seen.includes?(lk)
          yield({lk, vs.first})
        end
      end
    end

    struct ParamsView
      include Enumerable({String, String})
      @overlay : Hash(String, String)?

      def initialize(@src : HTTP::Params)
        @overlay = nil
      end

      def [](key : String) : String?
        @overlay.try(&.[key]?) || @src[key]?
      end

      def []?(key : String) : String?
        self[key]
      end

      def []=(key : String, value : String) : String
        (@overlay ||= {} of String => String)[key] = value
      end

      def each(& : {String, String} ->)
        seen = Set(String).new
        if ov = @overlay
          ov.each { |k, v| seen << k; yield({k, v}) }
        end
        @src.each { |k, v| next if seen.includes?(k); yield({k, v}) }
      end
    end
  end
end
