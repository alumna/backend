require "set"

module Alumna
  module Http
    macro define_overlay_view(name, source_type, downcase)
      struct {{name}}
        include Enumerable({String, String})
        @overlay : Hash(String, String)?

        def initialize(@src : {{source_type}})
          @overlay = nil
        end

        def [](key : String) : String
          self[key]? || raise KeyError.new("Missing hash key: #{key.inspect}")
        end

        def []?(key : String) : String?
          if ov = @overlay
            k = {% if downcase %} key.downcase {% else %} key {% end %}
            return ov[k] if ov.has_key?(k)
          end
          @src[key]?
        end

        def []=(key : String, value : String) : String
          (@overlay ||= {} of String => String)[{% if downcase %} key.downcase {% else %} key {% end %}] = value
        end

        def each(& : {String, String} ->)
          ov = @overlay
          if ov.nil?
            {% if downcase %}
              @src.each { |k, vs| yield({k.downcase, vs.first}) }
            {% else %}
              @src.each { |k, v| yield({k, v}) }
            {% end %}
            return
          end

          seen = Set(String).new
          ov.each { |k, v| seen << k; yield({k, v}) }

          {% if downcase %}
            @src.each do |k, vs|
              lk = k.downcase
              next if seen.includes?(lk)
              yield({lk, vs.first})
            end
          {% else %}
            @src.each do |k, v|
              next if seen.includes?(k)
              yield({k, v})
            end
          {% end %}
        end
      end
    end

    define_overlay_view(HeadersView, HTTP::Headers, true)
    define_overlay_view(ParamsView, HTTP::Params, false)
  end
end
