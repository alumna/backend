require "../spec_helper"

describe "Alumna::Types DX Helpers" do
  describe "Alumna.to_any" do
    it "safely upcasts Int variants to Int64 (AnyData)" do
      Alumna.to_any(42_i8).should be_a(Int64)
      Alumna.to_any(42_i16).should be_a(Int64)
      Alumna.to_any(42_i32).should be_a(Int64)
      Alumna.to_any(42_u8).should be_a(Int64)
      Alumna.to_any(42_u32).should be_a(Int64)

      Alumna.to_any(42_i32).as(Int64).should eq(42_i64)
    end

    it "safely upcasts Float32 to Float64 (AnyData)" do
      val = 3.14_f32
      result = Alumna.to_any(val)

      result.should be_a(Float64)
      result.as(Float64).should be_close(3.14, 0.001)
    end

    it "passes native AnyData types straight through" do
      t = Time.utc
      b = Bytes[1, 255]

      Alumna.to_any("hello").should eq("hello")
      Alumna.to_any(true).should be_true
      Alumna.to_any(t).should eq(t)
      Alumna.to_any(b).should eq(b)
    end
  end

  describe "Alumna.hash macro" do
    it "constructs a strict Hash(String, AnyData) automatically upcasting primitives" do
      h = Alumna.hash(
        str: "Alice",
        int: 30,         # Int32 -> Int64
        float: 3.14_f32, # Float32 -> Float64
        active: true
      )

      h.should be_a(Hash(String, Alumna::AnyData))
      h["str"].should eq("Alice")
      h["int"].should be_a(Int64)
      h["int"].should eq(30_i64)
      h["float"].should be_a(Float64)
      h["active"].should be_true
    end
  end

  describe "Array(T)#to_any" do
    it "converts arrays of Int32/Float32 into Array(AnyData)" do
      arr_int = [1, 2, 3].to_any
      arr_int.should be_a(Array(Alumna::AnyData))
      arr_int.first.should be_a(Int64)
      arr_int.first.should eq(1_i64)

      arr_float = [1.5_f32, 2.5_f32].to_any
      arr_float.should be_a(Array(Alumna::AnyData))
      arr_float.first.should be_a(Float64)
    end

    it "converts arrays of Strings cleanly" do
      arr_str = ["a", "b"].to_any
      arr_str.should be_a(Array(Alumna::AnyData))
      arr_str.first.should eq("a")
    end
  end

  describe "Hash deep fetching (dig_any? and dig_any)" do
    data = Alumna.hash(
      flat: "value",
      "literal.dot": "flat_key",
      user: Alumna.hash(
        profile: Alumna.hash(
          age: 30,
          active: true
        )
      )
    )

    it "fetches top-level keys normally" do
      data.dig_any?("flat").should eq("value")
      data.dig_any("flat").should eq("value")
    end

    it "prioritizes exact key matches over dot-notation (fast path)" do
      # If a key literally has a dot in it, it shouldn't traverse
      data.dig_any?("literal.dot").should eq("flat_key")
      data.dig_any("literal.dot").should eq("flat_key")
    end

    it "traverses nested hashes safely using dot-notation" do
      data.dig_any?("user.profile.age").should eq(30_i64)
      data.dig_any("user.profile.age").should eq(30_i64)
    end

    it "returns nil safely if a path is missing in dig_any?" do
      data.dig_any?("missing").should be_nil
      data.dig_any?("user.missing").should be_nil
      data.dig_any?("user.profile.missing").should be_nil
    end

    it "returns nil safely if the path tries to traverse into a non-hash" do
      # 'flat' is a String. Trying to get 'flat.missing' should abort and return nil.
      data.dig_any?("flat.missing").should be_nil
    end

    it "raises KeyError on strict dig_any when path is missing" do
      expect_raises(KeyError, /Missing hash path: "user.missing"/) do
        data.dig_any("user.missing")
      end
    end

    it "returns nil safely at compile-time if the Hash does not have String keys" do
      int_hash = {1 => "one", 2 => "two"}
      int_hash.dig_any?("1").should be_nil

      sym_hash = {:a => "alpha"}
      sym_hash.dig_any?("a").should be_nil
    end
  end

  describe "Hash Typed Accessors (dig_str, dig_int, etc.)" do
    t = Time.utc
    b = Bytes[255, 0]

    data = Alumna.hash(
      str_val: "text",
      int_val: 42,
      float_val: 3.14,
      bool_val: true,
      time_val: t,
      bytes_val: b
    )

    it "safely fetches and casts matching types (safe versions)" do
      data.dig_str?("str_val").should eq("text")
      data.dig_int?("int_val").should eq(42_i64)

      if val = data.dig_float?("float_val")
        val.should be_close(3.14, 0.001)
      else
        fail "expected float_val to be present and a Float64"
      end

      data.dig_bool?("bool_val").should be_true
      data.dig_time?("time_val").should eq(t)
      data.dig_bytes?("bytes_val").should eq(b)
    end

    it "returns nil if the key exists but the type is wrong (safe versions)" do
      data.dig_str?("int_val").should be_nil
      data.dig_int?("str_val").should be_nil
    end

    it "returns nil if the key is completely missing (safe versions)" do
      data.dig_str?("missing").should be_nil
    end

    it "fetches and casts matching types (strict versions)" do
      data.dig_str("str_val").should eq("text")
      data.dig_int("int_val").should eq(42_i64)
      data.dig_float("float_val").should be_close(3.14, 0.001)
      data.dig_bool("bool_val").should be_true
      data.dig_time("time_val").should eq(t)
      data.dig_bytes("bytes_val").should eq(b)
    end

    it "raises KeyError if the key is missing (strict versions)" do
      expect_raises(KeyError) { data.dig_str("missing") }
      expect_raises(KeyError) { data.dig_int("missing") }
    end

    it "raises TypeCastError if the key exists but the type is wrong (strict versions)" do
      expect_raises(TypeCastError) { data.dig_str("int_val") }
      expect_raises(TypeCastError) { data.dig_int("str_val") }
    end
  end
end
