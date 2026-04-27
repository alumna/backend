module Alumna
  module Http
    # Central registry for all wire formats.
    # Add new formats here - router and responder stay untouched.
    module Serializers
      JSON    = JsonSerializer.new
      MSGPACK = MsgpackSerializer.new

      # Fast lookup used by Router
      def self.from_content_type?(ct : String?) : Serializer?
        return nil unless ct
        ct = ct.downcase
        return MSGPACK if ct.includes?("msgpack")
        return JSON if ct.includes?("json")
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
