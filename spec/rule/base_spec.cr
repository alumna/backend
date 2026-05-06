require "../spec_helper"

private def dummy_ctx : Alumna::RuleContext
  app = Alumna::App.new
  service = Alumna::MemoryAdapter.new
  app.use("/dummy", service)
  Alumna::RuleContext.new(
    app: app,
    service: service,
    path: "/dummy",
    method: Alumna::ServiceMethod::Find,
    phase: Alumna::RulePhase::Before,
    params: Alumna::Http::ParamsView.new(HTTP::Params.new),
    headers: Alumna::Http::HeadersView.new(HTTP::Headers.new)
  )
end

def my_rule(ctx : Alumna::RuleContext) : Alumna::ServiceError?
  nil
end

describe "Alumna::Rule alias" do
  it "accepts a Proc that returns nil to continue" do
    rule = ->(ctx : Alumna::RuleContext) : Alumna::ServiceError? do
      ctx.headers["x"] = "1"
      nil
    end
    ctx = dummy_ctx
    err = rule.call(ctx)
    err.should be_nil
    ctx.headers["x"].should eq("1")
  end

  it "accepts a Proc that returns ServiceError to stop" do
    rule = Alumna::Rule.new { |ctx| Alumna::ServiceError.forbidden }
    err = rule.call(dummy_ctx)
    err.should_not be_nil
    err.as(Alumna::ServiceError).status.should eq(403)
  end

  it "works with a captured method" do
    rule = ->my_rule(Alumna::RuleContext) # my_rule already returns ServiceError?
    rule.call(dummy_ctx).should be_nil
  end
end
