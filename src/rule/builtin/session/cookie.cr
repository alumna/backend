module Alumna
  module Http
    # Finds one cookie by name in a Cookie header. Does not build a cookie list.
    # The value string is the only allocation. Name match is case-sensitive.
    def self.cookie_value(header : String, name : String) : String?
      return nil if name.empty?
      nsize = name.bytesize
      hsize = header.bytesize
      i = 0
      while i < hsize
        while i < hsize
          b = header.byte_at(i)
          break unless b == 0x20 || b == 0x09
          i += 1
        end
        break if i >= hsize

        if name_at?(header, i, name, nsize)
          eq = i + nsize
          if eq < hsize && header.byte_at(eq) == 0x3D
            start = eq + 1
            stop = start
            while stop < hsize && header.byte_at(stop) != 0x3B
              stop += 1
            end
            return header.byte_slice(start, stop - start)
          end
        end

        while i < hsize && header.byte_at(i) != 0x3B
          i += 1
        end
        i += 1 if i < hsize
      end
      nil
    end

    private def self.name_at?(header : String, i : Int32, name : String, nsize : Int32) : Bool
      return false if i + nsize > header.bytesize
      nsize.times do |j|
        return false unless header.byte_at(i + j) == name.byte_at(j)
      end
      true
    end
  end
end
