module Alumna
  enum ServiceMethod
    Find
    Get
    Create
    Update
    Patch
    Remove

    def to_s : String
      super.downcase
    end
  end
end
