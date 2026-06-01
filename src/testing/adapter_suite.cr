require "spec"

# ============================================================================
# Alumna Adapter Compliance Suite
# ============================================================================
# This suite guarantees that any custom database adapter (SQLite, Postgres,
# Redis, etc.) behaves exactly like the built-in MemoryAdapter.
#
# To test your adapter, simply call `Alumna::Testing::AdapterSuite.run`
# and yield a fresh instance of your adapter configured with the standard
# compliance schema (see the `MemoryAdapter` or `SqliteAdapter` specs for
# the exact schema definition).
#
# The suite will run dozens of automated edge-cases against your implementation,
# ensuring $gt, $in, pagination, and multi-threaded locks are perfectly compliant!
# ============================================================================

module Alumna
  module Testing
    module AdapterSuiteHelpers
      # Crystal's compiler sometimes struggles to auto-cast literals (like `10` or `"Alice"`)
      # deep inside nested Hash literals into union types like `AnyData`.
      # These `.any` overloads exist solely as a workaround to force the correct cast,
      # avoiding confusing type-mismatch compilation errors when users write adapter compliance tests.

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

      def self.any(v : Time) : AnyData
        v
      end

      def self.any(v : Bytes) : AnyData
        v
      end

      def self.insert(adapter : Service, data : Hash(String, AnyData))
        ctx = Alumna::Testing.build_ctx(
          service: adapter,
          method: ServiceMethod::Create,
          data: data
        )
        adapter.create(ctx).as(Hash(String, AnyData))
      end
    end

    module AdapterSuite
      macro run(name, &factory)
        describe {{name}} do
          describe "#create" do
            it "returns the record with an auto-assigned id" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              record = adapter.create(ctx).as(Hash(String, Alumna::AnyData))
              record["id"].should eq("1")
              record["name"].should eq("Alice")
            end

            it "auto-increments ids across successive calls" do
              adapter = begin
                {{factory.body}}
              end
              r1 = Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"title" => Alumna::Testing::AdapterSuiteHelpers.any("a")} of String => Alumna::AnyData)
              r2 = Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"title" => Alumna::Testing::AdapterSuiteHelpers.any("b")} of String => Alumna::AnyData)
              r1["id"].should eq("1")
              r2["id"].should eq("2")
            end

            it "overrides any id supplied in the input data with its own counter" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"id" => Alumna::Testing::AdapterSuiteHelpers.any("999"), "name" => Alumna::Testing::AdapterSuiteHelpers.any("Bob")} of String => Alumna::AnyData)
              record = adapter.create(ctx).as(Hash(String, Alumna::AnyData))
              record["id"].should eq("1")
            end

            it "persists the record so it can be retrieved afterwards" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              get_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "1")
              record = adapter.get(get_ctx).as(Hash(String, Alumna::AnyData))
              record["name"].should eq("Alice")
            end

            it "persists and retrieves Bytes" do
              adapter = begin
                {{factory.body}}
              end
              b = Bytes[10, 20]
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"blob" => Alumna::Testing::AdapterSuiteHelpers.any(b)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "1")
              rec = adapter.get(ctx).as(Hash(String, Alumna::AnyData))
              rec["blob"].should eq(b)
            end
          end

          describe "#find (filtering)" do
            it "returns an empty array when the store is empty" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
              adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).should be_empty
            end

            it "returns all records when no params are given" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Bob")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
              adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).size.should eq(2)
            end

            it "filters records by a single query param" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"role" => "admin"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["role"].should eq("admin")
            end

            it "applies AND semantics when multiple params are given" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin"), "active" => Alumna::Testing::AdapterSuiteHelpers.any(true)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin"), "active" => Alumna::Testing::AdapterSuiteHelpers.any(false)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("user"), "active" => Alumna::Testing::AdapterSuiteHelpers.any(true)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"role" => "admin", "active" => "true"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["role"].should eq("admin")
              results.first["active"].should eq(true)
            end

            it "returns an empty array when no records match the filter" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"role" => "admin"})
              adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).should be_empty
            end

            it "filters records using $ne operator" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"role[$ne]" => "admin"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["role"].should eq("user")
            end

            it "filters records using $gt and $lt operators on Int64" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(10)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(20)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(30)} of String => Alumna::AnyData)

              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"age[$gt]" => "15", "age[$lt]" => "25"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["age"].should eq(20)

              ctx2 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"age[$gt]" => "abc"})
              err = adapter.find(ctx2)
              err.should be_a(Alumna::ServiceError)
              err.as(Alumna::ServiceError).status.should eq(400)
            end

            it "filters records using $gt and $lt operators on Float64" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"rating" => Alumna::Testing::AdapterSuiteHelpers.any(3.5)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"rating" => Alumna::Testing::AdapterSuiteHelpers.any(4.5)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"rating" => Alumna::Testing::AdapterSuiteHelpers.any(5.0)} of String => Alumna::AnyData)

              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"rating[$gt]" => "4.0", "rating[$lt]" => "4.9"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["rating"].should eq(4.5)

              ctx2 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"rating[$gt]" => "abc"})
              err = adapter.find(ctx2)
              err.should be_a(Alumna::ServiceError)
              err.as(Alumna::ServiceError).status.should eq(400)
            end

            it "filters records using $gt and $lt operators on Bool" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"active" => Alumna::Testing::AdapterSuiteHelpers.any(true)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"active" => Alumna::Testing::AdapterSuiteHelpers.any(false)} of String => Alumna::AnyData)

              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"active[$gt]" => "false"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["active"].should eq(true)

              ctx2 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"active[$lt]" => "true"})
              results2 = adapter.find(ctx2).as(Array(Hash(String, Alumna::AnyData)))
              results2.size.should eq(1)
              results2.first["active"].should eq(false)

              ctx3 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"active[$gt]" => "not-a-bool"})
              err = adapter.find(ctx3)
              err.should be_a(Alumna::ServiceError)
              err.as(Alumna::ServiceError).status.should eq(400)
            end

            it "filters strings using $gt operator lexicographically" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"grade" => Alumna::Testing::AdapterSuiteHelpers.any("a")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"grade" => Alumna::Testing::AdapterSuiteHelpers.any("b")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"grade" => Alumna::Testing::AdapterSuiteHelpers.any("c")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"grade[$gt]" => "a", "grade[$lt]" => "c"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["grade"].should eq("b")
            end

            it "filters records using $gte and $lte operators" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(10)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(20)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"age" => Alumna::Testing::AdapterSuiteHelpers.any(30)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"age[$gte]" => "20", "age[$lte]" => "30"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(2)
              results.map(&.["age"]).should eq([20_i64, 30_i64])
            end

            it "filters records using $in operator" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("pending")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("active")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("archived")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"status[$in]" => "pending,active"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(2)
              results.map(&.["status"]).should eq(["pending", "active"])
            end

            it "filters records using $nin operator" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("pending")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("active")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"status" => Alumna::Testing::AdapterSuiteHelpers.any("archived")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"status[$nin]" => "pending,active"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["status"].should eq("archived")
            end

            it "filters records by nested fields using dot notation" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"user" => {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "age" => Alumna::Testing::AdapterSuiteHelpers.any(30)} of String => Alumna::AnyData} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"user" => {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Bob"), "age" => Alumna::Testing::AdapterSuiteHelpers.any(40)} of String => Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"user.name" => "Bob"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["user"].as(Hash(String, Alumna::AnyData))["name"].should eq("Bob")
            end

            it "filters array fields where an element matches the condition" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"tags" => [Alumna::Testing::AdapterSuiteHelpers.any("tech"), Alumna::Testing::AdapterSuiteHelpers.any("science")] of Alumna::AnyData} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"tags" => [Alumna::Testing::AdapterSuiteHelpers.any("art")] of Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"tags" => "tech"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["tags"].as(Array(Alumna::AnyData)).first.should eq("tech")
            end

            it "filters array fields where no element matches $ne" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"tags" => [Alumna::Testing::AdapterSuiteHelpers.any("tech"), Alumna::Testing::AdapterSuiteHelpers.any("science")] of Alumna::AnyData} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"tags" => [Alumna::Testing::AdapterSuiteHelpers.any("art")] of Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"tags[$ne]" => "tech"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["tags"].as(Array(Alumna::AnyData)).first.should eq("art")
            end

            it "filters records using $gt and $lt operators on Time" do
              adapter = begin
                {{factory.body}}
              end
              t1 = Time.utc(2024, 1, 1)
              t2 = Time.utc(2024, 2, 1)
              t3 = Time.utc(2024, 3, 1)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(t1)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(t2)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(t3)} of String => Alumna::AnyData)

              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"created[$gt]" => "2024-01-15T00:00:00Z", "created[$lt]" => "2024-02-15T00:00:00Z"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(1)
              results.first["created"].should eq(t2)

              ctx2 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"created[$gt]" => "invalid-date"})
              err = adapter.find(ctx2)
              err.should be_a(Alumna::ServiceError)
              err.as(Alumna::ServiceError).status.should eq(400)
            end

            it "filters records using $eq and $in operators on Time" do
              adapter = begin
                {{factory.body}}
              end
              t1 = Time.utc(2024, 1, 1, 12, 0, 0)
              t2 = Time.utc(2024, 1, 2, 12, 0, 0)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(t1)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(t2)} of String => Alumna::AnyData)

              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"created" => "2024-01-01T12:00:00Z"})
              res1 = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              res1.size.should eq(1)
              res1.first["created"].should eq(t1)

              ctx2 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"created[$in]" => "2024-01-01T12:00:00Z,2024-01-02T12:00:00Z"})
              res2 = adapter.find(ctx2).as(Array(Hash(String, Alumna::AnyData)))
              res2.size.should eq(2)
            end

            it "filters records using $ne and $nin operators on Time" do
              adapter = begin
                {{factory.body}}
              end
              t1 = Time.utc(2024, 1, 1, 12, 0, 0)
              t2 = Time.utc(2024, 1, 2, 12, 0, 0)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(t1)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(t2)} of String => Alumna::AnyData)

              # Cover the $ne branch
              ctx_ne = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"created[$ne]" => "2024-01-01T12:00:00Z"})
              res_ne = adapter.find(ctx_ne).as(Array(Hash(String, Alumna::AnyData)))
              res_ne.size.should eq(1)
              res_ne.first["created"].should eq(t2)

              # Cover the $nin branch
              ctx_nin = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"created[$nin]" => "2024-01-01T12:00:00Z"})
              res_nin = adapter.find(ctx_nin).as(Array(Hash(String, Alumna::AnyData)))
              res_nin.size.should eq(1)
              res_nin.first["created"].should eq(t2)
            end

            it "safely rejects maliciously forged programmatic query types on Time" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(Time.utc)} of String => Alumna::AnyData)

              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
              ctx.query.filters["created"] << Alumna::Query::Condition.new(Alumna::Query::Op::Ne, ["array", "instead", "of", "string"])
              err1 = adapter.find(ctx)
              err1.should be_a(Alumna::ServiceError)
              err1.as(Alumna::ServiceError).status.should eq(400)

              ctx2 = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
              ctx2.query.filters["created"] << Alumna::Query::Condition.new(Alumna::Query::Op::Nin, "string instead of array")
              err2 = adapter.find(ctx2)
              err2.should be_a(Alumna::ServiceError)
              err2.as(Alumna::ServiceError).status.should eq(400)
            end
          end

          describe "#find (sorting and limit/skip)" do
            it "applies $limit and $skip" do
              adapter = begin
                {{factory.body}}
              end
              5.times { |i| Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"sequence" => Alumna::Testing::AdapterSuiteHelpers.any(i.to_s)} of String => Alumna::AnyData) }
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$skip" => "1", "$limit" => "2"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(2)
              results.map(&.["sequence"]).should eq(["1", "2"])
            end

            it "applies $skip without $limit" do
              adapter = begin
                {{factory.body}}
              end
              5.times { |i| Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"sequence" => Alumna::Testing::AdapterSuiteHelpers.any(i.to_s)} of String => Alumna::AnyData) }
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$skip" => "2"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(3)
              results.map(&.["sequence"]).should eq(["2", "3", "4"])
            end

            it "safely handles $skip greater than the dataset size" do
              adapter = begin
                {{factory.body}}
              end
              3.times { |i| Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"sequence" => Alumna::Testing::AdapterSuiteHelpers.any(i.to_s)} of String => Alumna::AnyData) }
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$skip" => "10"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.should be_empty
            end

            it "applies $sort correctly with numeric types (not lexicographical)" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"score" => Alumna::Testing::AdapterSuiteHelpers.any(100)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"score" => Alumna::Testing::AdapterSuiteHelpers.any(9)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"score" => Alumna::Testing::AdapterSuiteHelpers.any(25)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "score:1"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.map(&.["score"]).should eq([9_i64, 25_i64, 100_i64])
            end

            it "applies $sort correctly with mixed numbers (Int64 and Float64)" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"price" => Alumna::Testing::AdapterSuiteHelpers.any(10)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"price" => Alumna::Testing::AdapterSuiteHelpers.any(9.5)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "price:1"})
              adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).map(&.["price"]).should eq([9.5_f64, 10_i64])
            end

            it "handles missing values in $sort gracefully" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("A"), "order_index" => Alumna::Testing::AdapterSuiteHelpers.any(2)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("B")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "order_index:1"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.map(&.["name"]).should eq(["B", "A"])
            end

            it "applies $sort correctly with string types" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"category" => Alumna::Testing::AdapterSuiteHelpers.any("banana")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"category" => Alumna::Testing::AdapterSuiteHelpers.any("apple")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "category:1"})
              adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).map(&.["category"]).should eq(["apple", "banana"])
            end

            it "applies $sort correctly with boolean types" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"is_published" => Alumna::Testing::AdapterSuiteHelpers.any(true)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"is_published" => Alumna::Testing::AdapterSuiteHelpers.any(false)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "is_published:1"})
              adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).map(&.["is_published"]).should eq([false, true])
            end

            it "applies $sort using string fallback for mismatched types or complex structures" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"metadata" => Alumna::Testing::AdapterSuiteHelpers.any("10")} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"metadata" => Alumna::Testing::AdapterSuiteHelpers.any(2)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"metadata" => [Alumna::Testing::AdapterSuiteHelpers.any(1)] of Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "metadata:1"})
              adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).map(&.["metadata"]).should eq([2_i64, "10", [1_i64] of Alumna::AnyData])
            end

            it "sorts records by nested fields using dot notation" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"user" => {"age" => Alumna::Testing::AdapterSuiteHelpers.any(40)} of String => Alumna::AnyData} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"user" => {"age" => Alumna::Testing::AdapterSuiteHelpers.any(30)} of String => Alumna::AnyData} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "user.age:1"})
              results = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))
              results.size.should eq(2)
              results.first["user"].as(Hash(String, Alumna::AnyData))["age"].should eq(30)
            end

            it "applies $select" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"first_name" => Alumna::Testing::AdapterSuiteHelpers.any("1"), "last_name" => Alumna::Testing::AdapterSuiteHelpers.any("2")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$select" => "first_name"})
              rec = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).first
              rec.has_key?("first_name").should be_true
              rec.has_key?("last_name").should be_false
              rec.has_key?("id").should be_true
            end

            it "applies $select when id is explicitly requested" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"first_name" => Alumna::Testing::AdapterSuiteHelpers.any("1"), "last_name" => Alumna::Testing::AdapterSuiteHelpers.any("2")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$select" => "first_name,id"})
              rec = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).first
              rec.keys.sort!.should eq(["first_name", "id"])
            end

            it "applies $select on empty store" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$select" => "first_name"})
              adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).should be_empty
            end

            it "applies $sort correctly with Time types" do
              adapter = begin
                {{factory.body}}
              end
              t1 = Time.utc(2024, 1, 1)
              t2 = Time.utc(2024, 2, 1)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(t2)} of String => Alumna::AnyData)
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"created" => Alumna::Testing::AdapterSuiteHelpers.any(t1)} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find, params: {"$sort" => "created:1"})
              adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).map(&.["created"]).should eq([t1, t2])
            end
          end

          describe "#get" do
            it "returns the record for a known id" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "1")
              record = adapter.get(ctx).as(Hash(String, Alumna::AnyData))
              record["name"].should eq("Alice")
            end

            it "returns nil for an unknown id" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "99")
              adapter.get(ctx).should be_nil
            end

            it "returns nil when ctx.id is nil" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: nil)
              adapter.get(ctx).should be_nil
            end
          end

          describe "#update" do
            it "replaces the record entirely and returns it with the same id" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Update, id: "1", data: {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              record = adapter.update(ctx).as(Hash(String, Alumna::AnyData))
              record["id"].should eq("1")
              record["role"].should eq("admin")
            end
          end

          describe "#patch" do
            it "merges fields and preserves id" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: "1", data: {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              record = adapter.patch(ctx).as(Hash(String, Alumna::AnyData))
              record["name"].should eq("Alice")
              record["role"].should eq("admin")
              record["id"].should eq("1")
            end

            it "persists the merge so a subsequent get reflects it" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice"), "role" => Alumna::Testing::AdapterSuiteHelpers.any("user")} of String => Alumna::AnyData)
              patch_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: "1", data: {"role" => Alumna::Testing::AdapterSuiteHelpers.any("admin")} of String => Alumna::AnyData)
              adapter.patch(patch_ctx)

              get_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "1")
              record = adapter.get(get_ctx).as(Hash(String, Alumna::AnyData))
              record["name"].should eq("Alice")
              record["role"].should eq("admin")
            end

            it "returns a 404 error when the id does not exist" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: "99", data: {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Ghost")} of String => Alumna::AnyData)
              result = adapter.patch(ctx)
              result.should be_a(Alumna::ServiceError)
              result.as(Alumna::ServiceError).status.should eq(404)
            end

            it "returns a 400 error when ctx.id is nil" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Patch, id: nil, data: {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Ghost")} of String => Alumna::AnyData)
              result = adapter.patch(ctx)
              result.should be_a(Alumna::ServiceError)
              result.as(Alumna::ServiceError).status.should eq(400)
            end
          end

          describe "#remove" do
            it "deletes the record and returns nil" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Remove, id: "1")
              adapter.remove(ctx).should be_nil
            end

            it "makes the record unretrievable after deletion" do
              adapter = begin
                {{factory.body}}
              end
              Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"name" => Alumna::Testing::AdapterSuiteHelpers.any("Alice")} of String => Alumna::AnyData)
              remove_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Remove, id: "1")
              adapter.remove(remove_ctx)

              get_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: "1")
              adapter.get(get_ctx).should be_nil
            end

            it "returns a 404 error when the id does not exist" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Remove, id: "99")
              result = adapter.remove(ctx)
              result.should be_a(Alumna::ServiceError)
              result.as(Alumna::ServiceError).status.should eq(404)
            end

            it "returns a 400 error when ctx.id is nil" do
              adapter = begin
                {{factory.body}}
              end
              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Remove, id: nil)
              result = adapter.remove(ctx)
              result.should be_a(Alumna::ServiceError)
              result.as(Alumna::ServiceError).status.should eq(400)
            end
          end

          describe "concurrency" do
            it "assigns unique sequential ids under concurrent creates" do
              adapter = begin
                {{factory.body}}
              end
              count = 100
              done = Channel(Nil).new(count)

              count.times do
                spawn do
                  ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Create, data: {"title" => Alumna::Testing::AdapterSuiteHelpers.any("v")} of String => Alumna::AnyData)
                  adapter.create(ctx)
                  done.send(nil)
                end
              end

              count.times { done.receive }

              ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
              records = adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData)))

              records.size.should eq(count)
              ids = records.map { |rec| rec["id"].as(String).to_i64 }.sort!
              ids.should eq((1_i64..count.to_i64).to_a)
            end

            it "does not lose updates under concurrent patches to the same record" do
              adapter = begin
                {{factory.body}}
              end
              base = Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"view_count" => Alumna::Testing::AdapterSuiteHelpers.any(0_i64)} of String => Alumna::AnyData)
              id = base["id"].as(String)

              writers = 50
              done = Channel(Nil).new(writers)

              writers.times do
                spawn do
                  get_ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: id)
                  if current = adapter.get(get_ctx).as?(Hash(String, Alumna::AnyData))
                    val = current["view_count"].as(Int64)
                    patch_ctx = Alumna::Testing.build_ctx(
                      service: adapter,
                      method: Alumna::ServiceMethod::Patch,
                      id: id,
                      data: {"view_count" => Alumna::Testing::AdapterSuiteHelpers.any(val + 1)} of String => Alumna::AnyData
                    )
                    adapter.patch(patch_ctx)
                  end
                  done.send(nil)
                end
                Fiber.yield
              end

              writers.times { done.receive }

              final = adapter.get(Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Get, id: id)).as?(Hash(String, Alumna::AnyData))
              final.should_not be_nil
              if final
                final["view_count"].as(Int64).should be >= 1
                final["view_count"].as(Int64).should be <= writers
                final["id"].as(String).should eq(id)
              end
            end

            it "allows concurrent finds while writing" do
              adapter = begin
                {{factory.body}}
              end
              done = Channel(Nil).new(2)

              spawn do
                50.times do |i|
                  Alumna::Testing::AdapterSuiteHelpers.insert(adapter, {"sequence" => Alumna::Testing::AdapterSuiteHelpers.any(i.to_i64)} of String => Alumna::AnyData)
                  Fiber.yield
                end
                done.send(nil)
              end

              spawn do
                50.times do
                  ctx = Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)
                  adapter.find(ctx).as(Array(Hash(String, Alumna::AnyData))).size.should be >= 0
                  Fiber.yield
                end
                done.send(nil)
              end

              2.times { done.receive }
              adapter.find(Alumna::Testing.build_ctx(service: adapter, method: Alumna::ServiceMethod::Find)).as(Array(Hash(String, Alumna::AnyData))).size.should eq(50)
            end
          end
        end
      end
    end
  end
end
