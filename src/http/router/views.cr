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
        if ov = @overlay
          k = key.downcase
          return ov[k] if ov.has_key?(k)
        end
        @src[key]?
      end

      def []?(key : String) : String?
        self[key]
      end

      def []=(key : String, value : String) : String
        (@overlay ||= {} of String => String)[key.downcase] = value
      end

      def each(& : {String, String} ->)
        ov = @overlay # local snapshot: type is Hash(String, String)?
        if ov.nil?    # after this branch + return, ov is Hash(String, String)
          @src.each { |k, vs| yield({k.downcase, vs.first}) }
          return
        end

        seen = Set(String).new
        ov.each { |k, v| seen << k; yield({k, v}) }
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
        ov = @overlay
        if ov.nil?
          @src.each { |k, v| yield({k, v}) }
          return
        end

        seen = Set(String).new
        ov.each { |k, v| seen << k; yield({k, v}) }
        @src.each { |k, v| next if seen.includes?(k); yield({k, v}) }
      end
    end
  end
end
