module Alumna
  module Http
    class LimitedIO < IO
      def initialize(@io : IO, @limit : Int64)
        @read = 0_i64
      end

      def read(slice : Bytes) : Int32
        raise IO::Error.new("exceeded") if @read >= @limit
        to_read = Math.min(slice.size, @limit - @read).to_i
        n = @io.read(slice[0, to_read])
        @read += n
        n
      end

      def write(slice : Bytes) : Nil
        raise IO::Error.new("write not supported")
      end
    end
  end
end
