require "../spec_helper"

describe Alumna::Query do
  it "parses filters, limit, skip, sort, select" do
    params = HTTP::Params.parse("name=Bob&$limit=2&$skip=1&$sort=age:-1&$select=id,name")
    q = Alumna::Query.new(Alumna::Http::ParamsView.new(params))

    q.filters["name"].first.value.should eq("Bob")
    q.filters["name"].first.op.should eq(Alumna::Query::Op::Eq)
    q.limit.should eq(2)
    q.skip.should eq(1)
    q.sort.should eq([{"age", -1}])
    q.select.should eq(["id", "name"])
  end

  it "ignores unknown $ keys" do
    params = HTTP::Params.parse("$foo=bar&x=1")
    q = Alumna::Query.new(Alumna::Http::ParamsView.new(params))
    q.filters["x"].first.value.should eq("1")
    q.filters.has_key?("$foo").should be_false
  end

  it "empty? is true for empty params and false otherwise" do
    q1 = Alumna::Query.new(Alumna::Http::ParamsView.new(HTTP::Params.new))
    q1.empty?.should be_true

    q2 = Alumna::Query.new(Alumna::Http::ParamsView.new(HTTP::Params.parse("x=1")))
    q2.empty?.should be_false
  end

  it "parses filter operators" do
    params = HTTP::Params.parse("age[$gt]=18&age[$lt]=30&status[$in]=active,pending&category[name]=tech")
    q = Alumna::Query.new(Alumna::Http::ParamsView.new(params))

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
end
