require "../spec_helper"

describe Alumna::ServiceMethod do
  it "renders as lowercase for logging and routing" do
    Alumna::ServiceMethod::Find.to_s.should eq("find")
    Alumna::ServiceMethod::Get.to_s.should eq("get")
    Alumna::ServiceMethod::Create.to_s.should eq("create")
    Alumna::ServiceMethod::Update.to_s.should eq("update")
    Alumna::ServiceMethod::Patch.to_s.should eq("patch")
    Alumna::ServiceMethod::Remove.to_s.should eq("remove")
    Alumna::ServiceMethod::Options.to_s.should eq("options")
  end

  it "round-trips through parse when lowercased then capitalized" do
    # this is the path used by your symbol-friendly API
    method = Alumna::ServiceMethod::Create
    parsed = Alumna::ServiceMethod.parse(method.to_s.capitalize)
    parsed.should eq(method)
  end
end
