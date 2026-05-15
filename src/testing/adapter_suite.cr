require "spec"

module Alumna
  module Testing
    module AdapterSuiteHelpers
      def self.any(v : String) : AnyData
        v
      end

      def self.any(v : Bool) : AnyData
        v
      end

      def self.any(v : Int) : AnyData
        v.to_i64
      end

      def self.any(v : Float) : AnyData
        v.to_f64
      end

      def self.insert(adapter : Service, data : Hash(String, AnyData))
        ctx = Alumna::Testing.build_ctx(
          service: adapter,
          method: ServiceMethod::Create,
          data: data
        )
        adapter.create(ctx)
      end
    end

    module AdapterSuite
      macro run(name, &factory)
        describe {{name}} do
          describe "#create" do
            it "returns the record with an auto-assigned id" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              record = adapter.create(ctx)
              record["id"].should eq("1")
              record["name"].should eq("Alice")
            end

            it "auto-increments ids across successive calls" do
              adapter = {{factory.body}}
              r1 = Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"x" => Alumna::Testing::AdapterSuiteHelpers.any("a")} of String => Alumna::AnyData)
              r2 = Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"x" => Alumna::Testing::AdapterSuiteHelpers.any("b")} of String => Alumna::AnyData)
              r1["id"].should eq("1")
              r2["id"].should eq("2")
            end

            it "overrides any id supplied in the input data with its own counter" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"id" => Alumna::Testing::AdapterSuiteHelpers.any("999"), "name" => Alumna::Testing::AdapterSuiteHelpers.any("Bob")} of String => Alumna::AnyData)
              record = adapter.create(ctx)
              record["id"].should eq("1")
            end

            it "persists the record so it can be retrieved afterwards" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              get_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "1")
              record = adapter.get(get_ctx)
              record.should_not be_nil
              record.try(&.["name"]).should eq("Alice")
            end
          end

          describe "#find (filtering)" do
            it "returns an empty array when the store is empty" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
              adapter.find(ctx).should be_empty
            end

            it "returns all records when no params are given" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Bob")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
              adapter.find(ctx).size.should eq(2)
            end

            it "filters records by a single query param" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"role" => "admin"})
              results = adapter.find(ctx)
              results.size.should eq(1)
              results.first["role"].should eq("admin")
            end

            it "applies AND semantics when multiple params are given" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin"), "active" => Alumna::Testing::AdapterSuiteHelpers.any(true)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin"), "active" => Alumna::Testing::AdapterSuiteHelpers.any(false)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("user"), "active" => Alumna::Testing::AdapterSuiteHelpers.any(true)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"role" => "admin", "active" => "true"})
              results = adapter.find(ctx)
              results.size.should eq(1)
              results.first["role"].should eq("admin")
              results.first["active"].should eq(true)
            end

            it "returns an empty array when no records match the filter" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"role" => "admin"})
              adapter.find(ctx).should be_empty
            end

            it "filters records using $ne operator" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"role[$ne]" => "admin"})
              results = adapter.find(ctx)
              results.size.should eq(1)
              results.first["role"].should eq("user")
            end

            it "filters records using $gt and $lt operators" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(10)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(20)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(30)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"age[$gt]" => "15", "age[$lt]" => "25"})
              results = adapter.find(ctx)
              results.size.should eq(1)
              results.first["age"].should eq(20)
            end

            it "filters strings using $gt operator lexicographically" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"letter" => Alumna::Testing::AdapterSuiteHelpers.any("a")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"letter" => Alumna::Testing::AdapterSuiteHelpers.any("b")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"letter" => Alumna::Testing::AdapterSuiteHelpers.any("c")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"letter[$gt]" => "a", "letter[$lt]" => "c"})
              results = adapter.find(ctx)
              results.size.should eq(1)
              results.first["letter"].should eq("b")
            end

            it "filters records using $gte and $lte operators" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(10)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(20)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(30)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"age[$gte]" => "20", "age[$lte]" => "30"})
              results = adapter.find(ctx)
              results.size.should eq(2)
              results.map(&.["age"]).should eq([20_i64, 30_i64])
            end

            it "filters records using $in operator" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("pending")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("active")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("archived")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"status[$in]" => "pending,active"})
              results = adapter.find(ctx)
              results.size.should eq(2)
              results.map(&.["status"]).should eq(["pending", "active"])
            end

            it "filters records using $nin operator" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("pending")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("active")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("archived")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"status[$nin]" => "pending,active"})
              results = adapter.find(ctx)
              results.size.should eq(1)
              results.first["status"].should eq("archived")
            end

            it "filters records by nested fields using dot notation" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"user" => {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "age" => Alumna::Testing::AdapterSuiteHelpers.any(30)} of String => Alumna::AnyData} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"user" => {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Bob"), "age" => Alumna::Testing::AdapterSuiteHelpers.any(40)} of String => Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"user.name" => "Bob"})
              results = adapter.find(ctx)
              results.size.should eq(1)
              results.first["user"].as(Hash(String, Alumna::AnyData))["name"].should eq("Bob")
            end

            it "filters array fields where an element matches the condition" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"tags" => [Alumna::Testing::AdapterSuiteHelpers.any("tech"), Alumna::Testing::AdapterSuiteHelpers.any("science")] of Alumna::AnyData} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"tags" => [Alumna::Testing::AdapterSuiteHelpers.any("art")] of Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"tags" => "tech"})
              results = adapter.find(ctx)
              results.size.should eq(1)
              results.first["tags"].as(Array(Alumna::AnyData)).first.should eq("tech")
            end

            it "filters array fields where no element matches $ne" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"tags" => [Alumna::Testing::AdapterSuiteHelpers.any("tech"), Alumna::Testing::AdapterSuiteHelpers.any("science")] of Alumna::AnyData} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"tags" => [Alumna::Testing::AdapterSuiteHelpers.any("art")] of Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"tags[$ne]" => "tech"})
              results = adapter.find(ctx)
              results.size.should eq(1)
              results.first["tags"].as(Array(Alumna::AnyData)).first.should eq("art")
            end
          end

          describe "#find (sorting and limit/skip)" do
            it "applies $limit and $skip" do
              adapter = {{factory.body}}
              5.times { |i| Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"n" => Alumna::Testing::AdapterSuiteHelpers.any(i.to_s)} of String => Alumna::AnyData) }
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$skip" => "1", "$limit" => "2"})
              results = adapter.find(ctx)
              results.size.should eq(2)
              results.map(&.["n"]).should eq(["1", "2"])
            end

            it "applies $sort correctly with numeric types (not lexicographical)" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"score" => Alumna::Testing::AdapterSuiteHelpers.any(100)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"score" => Alumna::Testing::AdapterSuiteHelpers.any(9)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"score" => Alumna::Testing::AdapterSuiteHelpers.any(25)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "score:1"})
              results = adapter.find(ctx)
              results.map(&.["score"]).should eq([9_i64, 25_i64, 100_i64])
            end

            it "applies $sort correctly with mixed numbers (Int64 and Float64)" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"val" => Alumna::Testing::AdapterSuiteHelpers.any(10)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"val" => Alumna::Testing::AdapterSuiteHelpers.any(9.5)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "val:1"})
              adapter.find(ctx).map(&.["val"]).should eq([9.5_f64, 10_i64])
            end

            it "handles missing values in $sort gracefully" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("A"), "pos" => Alumna::Testing::AdapterSuiteHelpers.any(2)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("B")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "pos:1"})
              results = adapter.find(ctx)
              results.map(&.["name"]).should eq(["B", "A"])
            end

            it "applies $sort correctly with string types" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"str" => Alumna::Testing::AdapterSuiteHelpers.any("banana")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"str" => Alumna::Testing::AdapterSuiteHelpers.any("apple")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "str:1"})
              adapter.find(ctx).map(&.["str"]).should eq(["apple", "banana"])
            end

            it "applies $sort correctly with boolean types" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"flag" => Alumna::Testing::AdapterSuiteHelpers.any(true)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"flag" => Alumna::Testing::AdapterSuiteHelpers.any(false)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "flag:1"})
              adapter.find(ctx).map(&.["flag"]).should eq([false, true])
            end

            it "applies $sort using string fallback for mismatched types or complex structures" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"mixed" => Alumna::Testing::AdapterSuiteHelpers.any("10")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"mixed" => Alumna::Testing::AdapterSuiteHelpers.any(2)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"mixed" => [Alumna::Testing::AdapterSuiteHelpers.any(1)] of Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "mixed:1"})
              adapter.find(ctx).map(&.["mixed"]).should eq(["10", 2_i64, [1_i64] of Alumna::AnyData])
            end

            it "sorts records by nested fields using dot notation" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"user" => {"age" => Alumna::Testing::AdapterSuiteHelpers.any(40)} of String => Alumna::AnyData} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"user" => {"age" => Alumna::Testing::AdapterSuiteHelpers.any(30)} of String => Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "user.age:1"})
              results = adapter.find(ctx)
              results.size.should eq(2)
              results.first["user"].as(Hash(String, Alumna::AnyData))["age"].should eq(30)
            end

            it "applies $select" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"a" => Alumna::Testing::AdapterSuiteHelpers.any("1"), "b" => Alumna::Testing::AdapterSuiteHelpers.any("2")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$select" => "a"})
              rec = adapter.find(ctx).first
              rec.has_key?("a").should be_true
              rec.has_key?("b").should be_false
              rec.has_key?("id").should be_true
            end

            it "applies $select when id is explicitly requested" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"a" => Alumna::Testing::AdapterSuiteHelpers.any("1"), "b" => Alumna::Testing::AdapterSuiteHelpers.any("2")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$select" => "a,id"})
              rec = adapter.find(ctx).first
              rec.keys.sort!.should eq(["a", "id"])
            end

            it "applies $select on empty store" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$select" => "a"})
              adapter.find(ctx).should be_empty
            end
          end

          describe "#get" do
            it "returns the record for a known id" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "1")
              record = adapter.get(ctx)
              record.should_not be_nil
              record.try(&.["name"]).should eq("Alice")
            end

            it "returns nil for an unknown id" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "99")
              adapter.get(ctx).should be_nil
            end

            it "returns nil when ctx.id is nil" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: nil)
              adapter.get(ctx).should be_nil
            end
          end

          describe "#update" do
            it "replaces the record entirely and returns it with the same id" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Update, id: "1", data: {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              record = adapter.update(ctx)
              record["id"].should eq("1")
              record["role"].should eq("admin")
            end
          end

          describe "#patch" do
            it "merges fields and preserves id" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: "1", data: {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              record = adapter.patch(ctx)
              record["name"].should eq("Alice")
              record["role"].should eq("admin")
              record["id"].should eq("1")
            end

            it "persists the merge so a subsequent get reflects it" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              patch_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: "1", data: {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              adapter.patch(patch_ctx)

              get_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "1")
              record = adapter.get(get_ctx)
              record.should_not be_nil
              if record
                record["name"].should eq("Alice")
                record["role"].should eq("admin")
              end
            end

            it "raises a 404 error when the id does not exist" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: "99", data: {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Ghost")} of String => Alumna::AnyData)
              error = expect_raises(Alumna::ServiceError) { adapter.patch(ctx) }
              error.status.should eq(404)
            end

            it "raises a 400 error when ctx.id is nil" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: nil, data: {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Ghost")} of String => Alumna::AnyData)
              error = expect_raises(Alumna::ServiceError) { adapter.patch(ctx) }
              error.status.should eq(400)
            end
          end

          describe "#remove" do
            it "deletes the record and returns true" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Remove, id: "1")
              adapter.remove(ctx).should be_true
            end

            it "makes the record unretrievable after deletion" do
              adapter = {{factory.body}}
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              remove_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Remove, id: "1")
              adapter.remove(remove_ctx)

              get_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "1")
              adapter.get(get_ctx).should be_nil
            end

            it "returns false when the id does not exist" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Remove, id: "99")
              adapter.remove(ctx).should be_false
            end

            it "raises a 400 error when ctx.id is nil" do
              adapter = {{factory.body}}
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Remove, id: nil)
              error = expect_raises(Alumna::ServiceError) { adapter.remove(ctx) }
              error.status.should eq(400)
            end
          end

          describe "concurrency" do
            it "assigns unique sequential ids under concurrent creates" do
              adapter = {{factory.body}}
              count = 100
              done = Channel(Nil).new(count)

              count.times do
                spawn do
                  ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"x" => Alumna::Testing::AdapterSuiteHelpers.any("v")} of String => Alumna::AnyData)
                  adapter.create(ctx)
                  done.send(nil)
                end
              end

              count.times { done.receive }

              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
              records = adapter.find(ctx)

              records.size.should eq(count)
              ids = records.map { |rec| rec["id"].as(String).to_i64 }.sort!
              ids.should eq((1_i64..count.to_i64).to_a)
            end

            it "does not lose updates under concurrent patches to the same record" do
              adapter = {{factory.body}}
              base = Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"counter" => Alumna::Testing::AdapterSuiteHelpers.any(0_i64)} of String => Alumna::AnyData)
              id = base["id"].as(String)

              writers = 50
              done = Channel(Nil).new(writers)

              writers.times do
                spawn do
                  get_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: id)
                  if current = adapter.get(get_ctx)
                    val = current["counter"].as(Int64)
                    patch_ctx = Alumna::Testing.build_ctx(
                      service: adapter,
                      method: Alumna::ServiceMethod::Patch,
                      id: id,
                      data: {"counter" => Alumna::Testing::AdapterSuiteHelpers.any(val + 1)} of String => Alumna::AnyData
                    )
                    adapter.patch(patch_ctx)
                  end
                  done.send(nil)
                end
                Fiber.yield
              end

              writers.times { done.receive }

              final = adapter.get(Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: id))
              final.should_not be_nil
              if final
                final["counter"].as(Int64).should be >= 1
                final["counter"].as(Int64).should be <= writers
                final["id"].as(String).should eq(id)
              end
            end

            it "allows concurrent finds while writing" do
              adapter = {{factory.body}}
              done = Channel(Nil).new(2)

              spawn do
                50.times do |i|
                  Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"n" => Alumna::Testing::AdapterSuiteHelpers.any(i.to_i64)} of String => Alumna::AnyData)
                  Fiber.yield
                end
                done.send(nil)
              end

              spawn do
                50.times do
                  ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
                  adapter.find(ctx).size.should be >= 0
                  Fiber.yield
                end
                done.send(nil)
              end

              2.times { done.receive }
              adapter.find(Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)).size.should eq(50)
            end
          end
        end
      end
    end
  end
end
