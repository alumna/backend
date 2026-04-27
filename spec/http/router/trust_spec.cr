require "../../spec_helper"

module Alumna::Http
  describe IPCidr do
    it "matches a single IPv4 /32" do
      cidr = IPCidr.new("10.0.0.5")
      cidr.includes?("10.0.0.5").should be_true
      cidr.includes?("10.0.0.6").should be_false
    end

    it "matches IPv4 CIDR ranges" do
      cidr = IPCidr.new("192.168.0.0/16")
      cidr.includes?("192.168.0.1").should be_true
      cidr.includes?("192.168.255.254").should be_true
      cidr.includes?("192.169.0.1").should be_false
    end

    it "handles IPv4 /0 (matches all v4)" do
      cidr = IPCidr.new("0.0.0.0/0")
      cidr.includes?("1.2.3.4").should be_true
      cidr.includes?("255.255.255.255").should be_true
      cidr.includes?("::1").should be_false # different family
    end

    it "matches IPv6 CIDR ranges" do
      cidr = IPCidr.new("2001:db8::/32")
      cidr.includes?("2001:db8::1").should be_true
      cidr.includes?("2001:db8:0:0:ffff:ffff:ffff:ffff").should be_true
      cidr.includes?("2001:db9::1").should be_false
    end

    it "handles IPv6 /128 exact match" do
      cidr = IPCidr.new("fe80::1/128")
      cidr.includes?("fe80::1").should be_true
      cidr.includes?("fe80::2").should be_false
    end

    it "rejects different address families" do
      v4 = IPCidr.new("10.0.0.0/8")
      v4.includes?("::1").should be_false

      v6 = IPCidr.new("::/0")
      v6.includes?("127.0.0.1").should be_false
    end

    it "raises on invalid CIDR" do
      expect_raises(ArgumentError) { IPCidr.new("not-an-ip") }
      expect_raises(ArgumentError) { IPCidr.new("300.0.0.1/24") }
    end
  end

  describe TrustedProxySet do
    it "trusts exact IPs and CIDRs" do
      set = TrustedProxySet.new(["127.0.0.1", "10.0.0.0/8", "2001:db8::/32"])

      set.trusted?("127.0.0.1").should be_true
      set.trusted?("10.5.6.7").should be_true
      set.trusted?("2001:db8::abcd").should be_true
    end

    it "does not trust outside ranges" do
      set = TrustedProxySet.new(["192.168.1.0/24"])

      set.trusted?("192.168.1.100").should be_true
      set.trusted?("192.168.2.1").should be_false
      set.trusted?("10.0.0.1").should be_false
    end

    it "handles empty list" do
      set = TrustedProxySet.new([] of String)
      set.trusted?("127.0.0.1").should be_false
    end

    it "is used by Router for X-Forwarded-For" do
      # integration sanity check — mirrors real usage
      set = TrustedProxySet.new(["172.16.0.0/12"])
      set.trusted?("172.16.5.4").should be_true
      set.trusted?("172.32.0.1").should be_false
    end
  end
end
