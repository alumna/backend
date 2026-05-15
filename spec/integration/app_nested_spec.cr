require "../spec_helper"
require "../../src/testing"

# 1. Define a complex schema with all nested features
OrganizationSchema = Alumna::Schema.new
  .str("name")
  .hash("billing") do |sub|
    sub.str("plan")
    sub.int("card_last_four", required: false)
  end
  .array("tags", of: :str, min_length: 1, max_length: 3)
  .array("members") do |sub|
    sub.str("email", format: :email)
    sub.str("role")
  end

# 2. Spin up a test application
APP_NESTED = Alumna::App.new.tap do |app|
  app.use("/orgs", Alumna.memory(OrganizationSchema) {
    # Run the built-in validation rule on create, update, and patch
    before validate, on: :write
  })
end

# 3. Helper for our test client
def nested_client
  Alumna::Testing::AppClient.new(APP_NESTED).tap do |c|
    c.default_headers["Content-Type"] = "application/json"
  end
end

describe "Alumna Integration: Nested Fields" do
  it "creates a valid record with deep nesting" do
    valid_payload = {
      "name"    => "Acme Corp",
      "billing" => {
        "plan"           => "enterprise",
        "card_last_four" => 4242_i64,
      },
      "tags"    => ["b2b", "saas"],
      "members" => [
        {"email" => "alice@acme.com", "role" => "admin"},
        {"email" => "bob@acme.com", "role" => "editor"},
      ],
    }

    res = nested_client.post("/orgs", body: valid_payload.to_json)

    res.status.should eq(201)

    # Ensure data was persisted correctly
    data = res.json
    data["id"].as_s.should match(/^\d+$/)
    data["name"].as_s.should eq("Acme Corp")
    data["billing"]["plan"].as_s.should eq("enterprise")
    data["tags"][1].as_s.should eq("saas")
    data["members"][0]["email"].as_s.should eq("alice@acme.com")
  end

  it "returns dot-notation errors for invalid nested hashes" do
    invalid_payload = {
      "name"    => "Acme Corp",
      "billing" => {
        # missing "plan"
        "card_last_four" => "not-a-number", # wrong type
      },
      "tags"    => ["b2b"],
      "members" => [] of String,
    }

    res = nested_client.post("/orgs", body: invalid_payload.to_json)

    res.status.should eq(422)
    details = res.json["details"]

    details["billing.plan"].as_s.should eq("is required")
    details["billing.card_last_four"].as_s.should eq("must be an integer")
  end

  it "returns bracket-notation errors for invalid array items (primitives)" do
    invalid_payload = {
      "name"    => "Acme Corp",
      "billing" => {"plan" => "pro"},
      "tags"    => ["valid", 123_i64, true], # index 1 and 2 are invalid
      "members" => [] of String,
    }

    res = nested_client.post("/orgs", body: invalid_payload.to_json)

    res.status.should eq(422)
    details = res.json["details"]

    details["tags[1]"].as_s.should eq("must be a string")
    details["tags[2]"].as_s.should eq("must be a string")
  end

  it "validates constraints applied directly to the array (min_length/max_length)" do
    invalid_payload = {
      "name"    => "Acme Corp",
      "billing" => {"plan" => "pro"},
      "tags"    => [] of String, # violates min_length: 1
      "members" => [] of String,
    }

    res = nested_client.post("/orgs", body: invalid_payload.to_json)

    res.status.should eq(422)
    details = res.json["details"]

    # Error should be on the array itself, not an index
    details["tags"].as_s.should eq("must contain at least 1 item")
  end

  it "returns dot-and-bracket notation errors for invalid array of objects" do
    invalid_payload = {
      "name"    => "Acme Corp",
      "billing" => {"plan" => "pro"},
      "tags"    => ["tech"],
      "members" => [
        {"email" => "alice@acme.com", "role" => "admin"}, # valid
        {"email" => "not-an-email", "role" => "editor"},  # invalid format
        {"role" => "viewer"},                             # missing required field
      ],
    }

    res = nested_client.post("/orgs", body: invalid_payload.to_json)

    res.status.should eq(422)
    details = res.json["details"]

    details["members[1].email"].as_s.should eq("must be a valid email address")
    details["members[2].email"].as_s.should eq("is required")
  end

  it "catches when an array of objects receives primitive elements instead" do
    invalid_payload = {
      "name"    => "Acme Corp",
      "billing" => {"plan" => "pro"},
      "tags"    => ["tech"],
      "members" => [
        "this-should-be-an-object",
      ],
    }

    res = nested_client.post("/orgs", body: invalid_payload.to_json)

    res.status.should eq(422)
    res.json["details"]["members[0]"].as_s.should eq("must be an object")
  end

  it "catches when a hash field receives a non-object" do
    invalid_payload = {
      "name"    => "Acme Corp",
      "billing" => "I should be a hash",
      "tags"    => ["tech"],
      "members" => [] of String,
    }

    res = nested_client.post("/orgs", body: invalid_payload.to_json)

    res.status.should eq(422)
    res.json["details"]["billing"].as_s.should eq("must be an object")
  end
end
