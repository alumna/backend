module Alumna
  module Http
    # Enforces max_body_size on *every* read entry point.
    # Raises IO::Error("exceeded") the moment the limit is hit,
    # so the router can turn it into 413 immediately.
    class LimitedIO < IO
      def initialize(@io : IO, @limit : Int64)
        @read = 0_i64
      end

      def read(slice : Bytes) : Int32
        raise IO::Error.new("exceeded") if @read >= @limit
        to_read = Math.min(slice.size.to_i64, @limit - @read).to_i
        n = @io.read(slice[0, to_read])
        @read += n
        n
      end

      def write(slice : Bytes) : Nil
        raise IO::Error.new("write not supported")
      end

      # --- completeness: all read paths must enforce the limit ---

      def read_byte : UInt8?
        raise IO::Error.new("exceeded") if @read >= @limit
        byte = @io.read_byte
        @read += 1 if byte
        byte
      end

      def peek : Bytes?
        return Bytes.empty if @read >= @limit
        if peeked = @io.peek
          remaining = @limit - @read
          peeked.size > remaining ? peeked[0, remaining.to_i] : peeked
        end
      end

      def skip(bytes_count) : Nil
        raise IO::Error.new("exceeded") if @read >= @limit
        to_skip = Math.min(bytes_count.to_i64, @limit - @read)
        @io.skip(to_skip)
        @read += to_skip
      end

      # delegate lifecycle
      def close
        @io.close
      end

      def closed?
        @io.closed?
      end
    end
  end
end
