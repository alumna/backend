module Alumna
  enum ServiceMethod
    Find
    Get
    Create
    Update
    Patch
    Remove
    Options

    def to_s : String
      super.downcase
    end

    def read? : Bool
      find? || get?
    end

    def write? : Bool
      create? || update? || patch?
    end

    # Create, update, patch, and remove. `:write` does not include remove.
    def mutate? : Bool
      write? || remove?
    end
  end
end
