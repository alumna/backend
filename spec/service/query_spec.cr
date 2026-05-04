require "../spec_helper"

describe Alumna::Query do
  it "parses filters, limit, skip, sort, select" do
    params = HTTP::Params.parse("name=Bob&$limit=2&$skip=1&$sort=age:-1&$select=id,name")
    q = Alumna::Query.new(Alumna::Http::ParamsView.new(params))

    q.filters["name"].should eq("Bob")
    q.limit.should eq(2)
    q.skip.should eq(1)
    q.sort.should eq([{"age", -1}])
    q.select.should eq(["id", "name"])
  end

  it "ignores unknown $ keys" do
    params = HTTP::Params.parse("$foo=bar&x=1")
    q = Alumna::Query.new(Alumna::Http::ParamsView.new(params))
    q.filters["x"].should eq("1")
    q.filters.has_key?("$foo").should be_false
  end

  it "empty? is true for empty params and false otherwise" do
    q1 = Alumna::Query.new(Alumna::Http::ParamsView.new(HTTP::Params.new))
    q1.empty?.should be_true

    q2 = Alumna::Query.new(Alumna::Http::ParamsView.new(HTTP::Params.parse("x=1")))
    q2.empty?.should be_false
  end
end
