module Alumna
  module Http
    struct IPCidr
      @family : Socket::Family
      @network_v4 : UInt32 = 0_u32
      @network_v6 : UInt128 = 0_u128
      @mask_bits : Int32

      def initialize(cidr : String)
        parts = cidr.split('/', 2)
        ip = parts[0]
        bits = parts[1]?

        if v4 = Socket::IPAddress.parse_v4_fields?(ip)
          @family = Socket::Family::INET
          @mask_bits = (bits || "32").to_i
          @network_v4 = v4.reduce(0_u32) { |a, b| (a << 8) | b }
        elsif v6 = Socket::IPAddress.parse_v6_fields?(ip)
          @family = Socket::Family::INET6
          @mask_bits = (bits || "128").to_i
          @network_v6 = v6.reduce(0_u128) { |a, b| (a << 16) | b }
        else
          raise ArgumentError.new("Invalid IP/CIDR: #{cidr}")
        end
      end

      def includes?(ip : String) : Bool
        if v4 = Socket::IPAddress.parse_v4_fields?(ip)
          return false unless @family.inet?
          ip_int = v4.reduce(0_u32) { |a, b| (a << 8) | b }
          mask = @mask_bits == 0 ? 0_u32 : (~0_u32 << (32 - @mask_bits))
          (ip_int & mask) == (@network_v4 & mask)
        elsif v6 = Socket::IPAddress.parse_v6_fields?(ip)
          return false unless @family.inet6?
          ip_int = v6.reduce(0_u128) { |a, b| (a << 16) | b }
          mask = @mask_bits == 0 ? 0_u128 : (~0_u128 << (128 - @mask_bits))
          (ip_int & mask) == (@network_v6 & mask)
        else
          false
        end
      end
    end

    struct TrustedProxySet
      @cidrs : Array(IPCidr)

      def initialize(list : Array(String))
        @cidrs = list.map { |c| IPCidr.new(c) }
      end

      def trusted?(ip : String) : Bool
        @cidrs.any?(&.includes?(ip))
      end
    end
  end
end
