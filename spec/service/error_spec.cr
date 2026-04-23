require "../spec_helper"

describe Alumna::ServiceError do
  describe "initialization" do
    it "stores message, status, and details" do
      err = Alumna::ServiceError.new("boom", 418, {"field" => "bad"} of String => Alumna::AnyData)
      err.message.should eq("boom")
      err.status.should eq(418)
      err.details.should eq({"field" => "bad"} of String => Alumna::AnyData)
    end

    it "defaults status to 400 and details to empty hash" do
      err = Alumna::ServiceError.new("bad")
      err.status.should eq(400)
      err.details.empty?.should be_true
    end

    it "is an Exception" do
      err = Alumna::ServiceError.new("x")
      (err.is_a?(Exception)).should be_true
    end

    it "can be raised and rescued" do
      rescued = false
      begin
        raise Alumna::ServiceError.new("test", 400)
      rescue ex : Alumna::ServiceError
        rescued = true
        ex.message.should eq("test")
      end
      rescued.should be_true
    end
  end

  describe ".bad_request" do
    it "returns 400 with custom message" do
      err = Alumna::ServiceError.bad_request("invalid")
      err.status.should eq(400)
      err.message.should eq("invalid")
    end

    it "accepts details hash" do
      err = Alumna::ServiceError.bad_request("invalid", {"id" => "required"} of String => Alumna::AnyData)
      err.details["id"].should eq("required")
    end
  end

  describe ".unauthorized" do
    it "defaults message to Unauthorized and status 401" do
      err = Alumna::ServiceError.unauthorized
      err.status.should eq(401)
      err.message.should eq("Unauthorized")
    end

    it "allows custom message" do
      err = Alumna::ServiceError.unauthorized("no token")
      err.message.should eq("no token")
      err.status.should eq(401)
    end
  end

  describe ".forbidden" do
    it "defaults to Forbidden 403" do
      err = Alumna::ServiceError.forbidden
      err.status.should eq(403)
      err.message.should eq("Forbidden")
    end

    it "allows custom message" do
      err = Alumna::ServiceError.forbidden("admin only")
      err.message.should eq("admin only")
    end
  end

  describe ".not_found" do
    it "defaults to Not found 404" do
      err = Alumna::ServiceError.not_found
      err.status.should eq(404)
      err.message.should eq("Not found")
    end

    it "allows custom message" do
      err = Alumna::ServiceError.not_found("No service at /x")
      err.message.should eq("No service at /x")
      err.status.should eq(404)
    end
  end

  describe ".unprocessable" do
    it "returns 422 with message and details" do
      details = {"title" => "is required", "email" => "must be a valid email address"} of String => Alumna::AnyData
      err = Alumna::ServiceError.unprocessable("Validation failed", details)
      err.status.should eq(422)
      err.message.should eq("Validation failed")
      err.details.should eq(details)
    end

    it "defaults details to empty hash" do
      err = Alumna::ServiceError.unprocessable("Validation failed")
      err.details.empty?.should be_true
    end
  end

  describe ".internal" do
    it "defaults to Internal server error 500" do
      err = Alumna::ServiceError.internal
      err.status.should eq(500)
      err.message.should eq("Internal server error")
    end

    it "allows custom message" do
      err = Alumna::ServiceError.internal("db down")
      err.message.should eq("db down")
      err.status.should eq(500)
    end
  end
end
