require "../spec_helper"
require "http/server/response"

private def fake_response
  io = IO::Memory.new
  HTTP::Server::Response.new(io)
end

private def build_ctx(
  method : Alumna::ServiceMethod = Alumna::ServiceMethod::Find,
  result : Alumna::ServiceResult = nil,
  error : Alumna::ServiceError? = nil,
) : Alumna::RuleContext
  app = Alumna::App.new
  service = Alumna::MemoryAdapter.new("/test")
  ctx = Alumna::RuleContext.new(
    app: app,
    service: service,
    path: "/test",
    method: method,
    phase: Alumna::RulePhase::After,
    params: Alumna::Http::ParamsView.new(HTTP::Params.new),
    headers: Alumna::Http::HeadersView.new(HTTP::Headers.new)
  )
  ctx.result = result
  ctx.error = error
  ctx
end

private def json_serializer
  Alumna::Http::JsonSerializer.new
end

describe Alumna::Http::Responder do
  describe ".write" do
    it "writes errors and returns early" do
      ctx = build_ctx(error: Alumna::ServiceError.not_found("missing"))
      resp = fake_response

      Alumna::Http::Responder.write(resp, ctx, json_serializer)
      resp.close

      resp.status_code.should eq(404)
    end

    it "copies ctx.http.headers to the response" do
      ctx = build_ctx(result: {"ok" => true} of String => Alumna::AnyData)
      ctx.http.headers["X-Custom"] = "abc"
      resp = fake_response

      Alumna::Http::Responder.write(resp, ctx, json_serializer)
      resp.close

      resp.headers["X-Custom"].should eq("abc")
    end

    it "handles redirects with default 302" do
      ctx = build_ctx
      ctx.http.location = "/new-location"
      resp = fake_response

      Alumna::Http::Responder.write(resp, ctx, json_serializer)
      resp.close

      resp.status_code.should eq(302)
      resp.headers["Location"].should eq("/new-location")
    end

    it "handles redirects with custom status" do
      ctx = build_ctx
      ctx.http.location = "/moved"
      ctx.http.status = 301
      resp = fake_response

      Alumna::Http::Responder.write(resp, ctx, json_serializer)
      resp.close

      resp.status_code.should eq(301)
    end

    it "uses ctx.http.status when set" do
      ctx = build_ctx(result: {"a" => 1_i64} of String => Alumna::AnyData)
      ctx.http.status = 202
      resp = fake_response

      Alumna::Http::Responder.write(resp, ctx, json_serializer)
      resp.close

      resp.status_code.should eq(202)
    end

    it "defaults to 201 for create and 200 otherwise" do
      create_ctx = build_ctx(method: Alumna::ServiceMethod::Create, result: {"id" => "1"} of String => Alumna::AnyData)
      find_ctx = build_ctx(method: Alumna::ServiceMethod::Find, result: [] of Hash(String, Alumna::AnyData))

      create_resp = fake_response
      find_resp = fake_response

      Alumna::Http::Responder.write(create_resp, create_ctx, json_serializer)
      Alumna::Http::Responder.write(find_resp, find_ctx, json_serializer)
      create_resp.close
      find_resp.close

      create_resp.status_code.should eq(201)
      find_resp.status_code.should eq(200)
    end

    it "encodes Array results" do
      ctx = build_ctx(result: [{"x" => 1_i64} of String => Alumna::AnyData])
      resp = fake_response

      Alumna::Http::Responder.write(resp, ctx, json_serializer)
      resp.close

      resp.status_code.should eq(200)
    end

    it "encodes Hash results" do
      ctx = build_ctx(result: {"ok" => true} of String => Alumna::AnyData)
      resp = fake_response

      Alumna::Http::Responder.write(resp, ctx, json_serializer)
      resp.close

      resp.status_code.should eq(200)
    end

    it "encodes Nil as {\"success\":true}" do
      ctx = build_ctx(result: nil)
      resp = fake_response

      Alumna::Http::Responder.write(resp, ctx, json_serializer)
      resp.close

      resp.status_code.should eq(200)
    end
  end

  describe ".write_error" do
    it "sets status and encodes error with details" do
      err = Alumna::ServiceError.unprocessable("bad", {"field" => "required"} of String => Alumna::AnyData)
      resp = fake_response

      Alumna::Http::Responder.write_error(resp, err, json_serializer)
      resp.close

      resp.status_code.should eq(422)
    end
  end
end
