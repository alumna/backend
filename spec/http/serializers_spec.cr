require "../spec_helper"

module Alumna::Http
  describe Serializers do
    # ── fast path (lowercase – no allocation) ──────────────────────────────

    describe ".from_content_type? fast path" do
      it "returns JSON for 'application/json'" do
        Serializers.from_content_type?("application/json").should be(Serializers::JSON)
      end

      it "returns JSON for 'application/json; charset=utf-8'" do
        Serializers.from_content_type?("application/json; charset=utf-8").should be(Serializers::JSON)
      end

      it "returns MSGPACK for 'application/msgpack'" do
        Serializers.from_content_type?("application/msgpack").should be(Serializers::MSGPACK)
      end

      it "returns MSGPACK for 'application/x-msgpack'" do
        Serializers.from_content_type?("application/x-msgpack").should be(Serializers::MSGPACK)
      end

      it "returns nil for 'text/plain'" do
        Serializers.from_content_type?("text/plain").should be_nil
      end

      it "returns nil for an empty string" do
        Serializers.from_content_type?("").should be_nil
      end

      it "returns nil for nil" do
        Serializers.from_content_type?(nil).should be_nil
      end
    end

    # ── slow path (non-lowercase – triggers downcase) ──────────────────────

    describe ".from_content_type? slow path" do
      it "returns JSON for 'Application/JSON'" do
        Serializers.from_content_type?("Application/JSON").should be(Serializers::JSON)
      end

      it "returns JSON for 'APPLICATION/JSON'" do
        Serializers.from_content_type?("APPLICATION/JSON").should be(Serializers::JSON)
      end

      it "returns JSON for 'Application/Json; charset=utf-8'" do
        Serializers.from_content_type?("Application/Json; charset=utf-8").should be(Serializers::JSON)
      end

      it "returns MSGPACK for 'application/MsgPack'" do
        Serializers.from_content_type?("application/MsgPack").should be(Serializers::MSGPACK)
      end

      it "returns MSGPACK for 'APPLICATION/MSGPACK'" do
        Serializers.from_content_type?("APPLICATION/MSGPACK").should be(Serializers::MSGPACK)
      end

      it "returns MSGPACK for 'Application/X-MsgPack'" do
        Serializers.from_content_type?("Application/X-MsgPack").should be(Serializers::MSGPACK)
      end

      it "returns nil for an unrecognised mixed-case type" do
        Serializers.from_content_type?("Text/HTML").should be_nil
      end
    end

    # ── from_accept? ───────────────────────────────────────────────────────

    describe ".from_accept?" do
      it "delegates to from_content_type? and returns JSON" do
        Serializers.from_accept?("application/json").should be(Serializers::JSON)
      end

      it "delegates to from_content_type? and returns MSGPACK" do
        Serializers.from_accept?("application/msgpack").should be(Serializers::MSGPACK)
      end

      it "delegates to from_content_type? for mixed-case input" do
        Serializers.from_accept?("Application/JSON").should be(Serializers::JSON)
      end

      it "returns nil for nil" do
        Serializers.from_accept?(nil).should be_nil
      end

      it "returns nil for an unrecognised type" do
        Serializers.from_accept?("text/html").should be_nil
      end
    end
  end
end
