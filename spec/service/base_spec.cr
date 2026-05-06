require "../spec_helper"

private class ExplodingService < Alumna::Service
  def initialize
    super()
  end

  def find(ctx) : Array(Hash(String, Alumna::AnyData))
    raise "kaboom"
  end

  def get(ctx) : Hash(String, Alumna::AnyData)?
    raise Exception.new
  end

  def create(ctx) : Hash(String, Alumna::AnyData)
    {} of String => Alumna::AnyData
  end

  def update(ctx) : Hash(String, Alumna::AnyData)
    {} of String => Alumna::AnyData
  end

  def patch(ctx) : Hash(String, Alumna::AnyData)
    {} of String => Alumna::AnyData
  end

  def remove(ctx) : Bool
    true
  end
end

private def dispatch(svc, method)
  app = Alumna::App.new
  app.use("/boom", svc)
  ctx = Alumna::RuleContext.new(
    app: app, service: svc, path: "/boom", method: method,
    phase: Alumna::RulePhase::Before,
    params: Alumna::Http::ParamsView.new(HTTP::Params.new),
    headers: Alumna::Http::HeadersView.new(HTTP::Headers.new)
  )
  app.dispatch(svc, ctx)
  ctx
end

describe "Service::Base" do
  describe "error boundary in call_method" do
    it "wraps a raised Exception with message into 500" do
      svc = ExplodingService.new
      ctx = dispatch(svc, Alumna::ServiceMethod::Find)

      ctx.error.should_not be_nil
      err = ctx.error.as(Alumna::ServiceError)
      err.status.should eq(500)
      err.message.should eq("kaboom")
      ctx.phase.should eq(Alumna::RulePhase::Error)
      ctx.result_set?.should be_false
    end

    it "uses 'Unexpected error' when Exception.message is nil" do
      svc = ExplodingService.new
      ctx = dispatch(svc, Alumna::ServiceMethod::Get)

      ctx.error.should_not be_nil
      ctx.error.as(Alumna::ServiceError).message.should eq("Unexpected error")
    end
  end
end
