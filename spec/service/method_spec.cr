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
    method = Alumna::ServiceMethod::Create
    parsed = Alumna::ServiceMethod.parse(method.to_s.capitalize)
    parsed.should eq(method)
  end

  it "identifies read and write methods" do
    Alumna::ServiceMethod::Find.read?.should be_true
    Alumna::ServiceMethod::Get.read?.should be_true
    Alumna::ServiceMethod::Create.read?.should be_false

    Alumna::ServiceMethod::Create.write?.should be_true
    Alumna::ServiceMethod::Update.write?.should be_true
    Alumna::ServiceMethod::Patch.write?.should be_true
    Alumna::ServiceMethod::Find.write?.should be_false
    Alumna::ServiceMethod::Remove.write?.should be_false
  end
end
