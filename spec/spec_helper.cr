require "spec"
require "../src/alumna"

def test_ctx(
  app = Alumna::App.new,
  service = Alumna::MemoryAdapter.new("/test"),
  path = "/test",
  method = Alumna::ServiceMethod::Find,
  phase = Alumna::RulePhase::Before,
) : Alumna::RuleContext
  Alumna::RuleContext.new(
    app: app,
    service: service,
    path: path,
    method: method,
    phase: phase,
    params: Alumna::Http::ParamsView.new(HTTP::Params.new),
    headers: Alumna::Http::HeadersView.new(HTTP::Headers.new)
  )
end
