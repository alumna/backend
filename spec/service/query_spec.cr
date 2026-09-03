require "../spec_helper"

private def query(qs : String, default_limit : Int32? = nil, max_limit : Int32? = nil)
  params = HTTP::Params.parse(qs)
  Alumna::Query.new(Alumna::Http::ParamsView.new(params), default_limit, max_limit)
end

private def empty_query(default_limit : Int32? = nil, max_limit : Int32? = nil)
  Alumna::Query.new(Alumna::Http::ParamsView.new(HTTP::Params.new), default_limit, max_limit)
end

describe Alumna::Query do
  it "parses filters, limit, skip, sort, select" do
    q = query("name=Bob&$limit=2&$skip=1&$sort=age:-1&$select=id,name")

    q.filters["name"].first.value.should eq("Bob")
    q.filters["name"].first.op.should eq(Alumna::Query::Op::Eq)
    q.limit.should eq(2)
    q.skip.should eq(1)
    q.sort.should eq([{"age", -1}])
    q.select.should eq(["id", "name"])
  end

  it "ignores unknown $ keys" do
    q = query("$foo=bar&x=1")
    q.filters["x"].first.value.should eq("1")
    q.filters.has_key?("$foo").should be_false
  end

  it "empty? is true for empty params and false otherwise" do
    q1 = empty_query
    q1.empty?.should be_true

    q2 = query("x=1")
    q2.empty?.should be_false
  end

  it "parses filter operators" do
    q = query("age[$gt]=18&age[$lt]=30&status[$in]=active,pending&category[name]=tech")

    q.filters["age"].size.should eq(2)
    q.filters["age"][0].op.should eq(Alumna::Query::Op::Gt)
    q.filters["age"][0].value.should eq("18")
    q.filters["age"][1].op.should eq(Alumna::Query::Op::Lt)
    q.filters["age"][1].value.should eq("30")

    q.filters["status"].size.should eq(1)
    q.filters["status"][0].op.should eq(Alumna::Query::Op::In)
    q.filters["status"][0].value.should eq(["active", "pending"])

    q.filters["category[name]"].size.should eq(1)
    q.filters["category[name]"][0].op.should eq(Alumna::Query::Op::Eq)
    q.filters["category[name]"][0].value.should eq("tech")
  end

  it "leaves limit nil when caps are unset and the client omits $limit" do
    empty_query.limit.should be_nil
    query("x=1").limit.should be_nil
    empty_query(max_limit: 5).limit.should be_nil
  end

  it "applies default_limit when the client omits $limit" do
    empty_query(default_limit: 3).limit.should eq(3)
    empty_query(default_limit: 0).limit.should eq(0)
  end

  it "keeps a client $limit when default_limit is also set" do
    query("$limit=4", default_limit: 1).limit.should eq(4)
  end

  it "clamps a client $limit that is above max_limit" do
    query("$limit=10", max_limit: 3).limit.should eq(3)
  end

  it "does not clamp a client $limit that is at or below max_limit" do
    query("$limit=3", max_limit: 3).limit.should eq(3)
    query("$limit=2", max_limit: 3).limit.should eq(2)
    query("$limit=0", max_limit: 3).limit.should eq(0)
  end

  it "uses the tighter of default_limit and max_limit" do
    empty_query(default_limit: 10, max_limit: 2).limit.should eq(2)
    empty_query(default_limit: 2, max_limit: 10).limit.should eq(2)
  end

  it "accepts $limit=0 and $skip=0" do
    q = query("$limit=0&$skip=0")
    q.limit.should eq(0)
    q.skip.should eq(0)
    q.typed_filters(nil).should be_a(Hash(String, Array(Alumna::Query::TypedCondition)))
  end

  it "returns 400 from typed_filters for invalid $limit" do
    {"abc", "", "-1", " 1", "1.5"}.each do |raw|
      q = query("$limit=#{raw}")
      q.limit.should be_nil
      err = q.typed_filters(nil)
      err.should be_a(Alumna::ServiceError)
      err.as(Alumna::ServiceError).status.should eq(400)
      err.as(Alumna::ServiceError).message.should eq("Invalid $limit")
    end
  end

  it "returns 400 from typed_filters for invalid $skip" do
    {"abc", "", "-1"}.each do |raw|
      q = query("$skip=#{raw}")
      q.skip.should be_nil
      err = q.typed_filters(nil)
      err.should be_a(Alumna::ServiceError)
      err.as(Alumna::ServiceError).status.should eq(400)
      err.as(Alumna::ServiceError).message.should eq("Invalid $skip")
    end
  end

  it "keeps the first parse error when both $limit and $skip are invalid" do
    err_limit = query("$limit=abc&$skip=xyz").typed_filters(nil)
    err_limit.as(Alumna::ServiceError).message.should eq("Invalid $limit")

    err_skip = query("$skip=xyz&$limit=abc").typed_filters(nil)
    err_skip.as(Alumna::ServiceError).message.should eq("Invalid $skip")
  end

  it "does not apply default_limit when the client sent an invalid $limit" do
    q = query("$limit=abc", default_limit: 5)
    q.limit.should be_nil
    q.typed_filters(nil).as(Alumna::ServiceError).status.should eq(400)
  end

  it "raises ArgumentError for negative default_limit or max_limit" do
    expect_raises(ArgumentError, "default_query_limit must be >= 0") do
      empty_query(default_limit: -1)
    end
    expect_raises(ArgumentError, "max_query_limit must be >= 0") do
      empty_query(max_limit: -1)
    end
  end
end

describe Alumna::App do
  it "defaults query limit caps to nil" do
    app = Alumna::App.new
    app.default_query_limit.should be_nil
    app.max_query_limit.should be_nil
  end

  it "accepts nil, zero, and positive query limit caps" do
    app = Alumna::App.new
    app.default_query_limit = 4
    app.max_query_limit = 8
    app.default_query_limit.should eq(4)
    app.max_query_limit.should eq(8)

    app.default_query_limit = 0
    app.max_query_limit = 0
    app.default_query_limit.should eq(0)
    app.max_query_limit.should eq(0)

    app.default_query_limit = nil
    app.max_query_limit = nil
    app.default_query_limit.should be_nil
    app.max_query_limit.should be_nil
  end

  it "raises ArgumentError for negative query limit caps" do
    app = Alumna::App.new
    expect_raises(ArgumentError, "default_query_limit must be >= 0") do
      app.default_query_limit = -1
    end
    expect_raises(ArgumentError, "max_query_limit must be >= 0") do
      app.max_query_limit = -1
    end
  end
end
