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
            {% if downcase %}
              ov.each { |k, v| return v if key.compare(k, case_insensitive: true) == 0 }
            {% end %}
            {% if !downcase %}
              return ov[key] if ov.has_key?(key)
            {% end %}
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
              @src.each do |k, vs|
                lk = k.downcase
                vs.each { |v| yield({lk, v}) }
              end
            {% end %}
            {% if !downcase %}
              @src.each { |k, v| yield({k, v}) }
            {% end %}
            return
          end

          ov.each { |k, v| yield({k, v}) }

          {% if downcase %}
            @src.each do |k, vs|
              next if ov.any? { |ok, _| k.compare(ok, case_insensitive: true) == 0 }
              lk = k.downcase
              vs.each { |v| yield({lk, v}) }
            end
          {% end %}
          {% if !downcase %}
            @src.each do |k, v|
              next if ov.has_key?(k)
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
