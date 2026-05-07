module Alumna
  module Http
    # Central registry for all wire formats.
    # Add new formats here - router and responder stay untouched.
    module Serializers
      JSON    = JsonSerializer.new
      MSGPACK = MsgpackSerializer.new

      def self.from_content_type?(ct : String?) : Serializer?
        return nil unless ct
        # Fast path: HTTP clients almost always send lowercase content types.
        # These checks are allocation-free.
        return MSGPACK if ct.includes?("msgpack")
        return JSON if ct.includes?("json")
        # Slow path: non-lowercase content type (rare in practice).
        # Pay the allocation cost only here.
        lc = ct.downcase
        return MSGPACK if lc.includes?("msgpack")
        return JSON if lc.includes?("json")
        nil
      end

      def self.from_accept?(accept : String?) : Serializer?
        from_content_type?(accept)
      end

      # Future: allow plugins
      # def self.register(mime : Regex, serializer : Serializer)
    end
  end
end
