module Alumna
  # A Rule is simply a Proc that receives a context and returns a RuleResult.
  # This alias means any method, lambda, or proc with the right signature qualifies.
  alias Rule = Proc(RuleContext, RuleResult)

  struct RuleResult
    getter outcome : Outcome
    getter error : ServiceError?

    enum Outcome
      Continue
      Stop
    end

    def self.continue : RuleResult
      new(Outcome::Continue, nil)
    end

    def self.stop(error : ServiceError) : RuleResult
      new(Outcome::Stop, error)
    end

    def continue? : Bool
      @outcome.continue?
    end

    def stop? : Bool
      @outcome.stop?
    end

    private def initialize(@outcome : Outcome, @error : ServiceError?)
    end
  end
end
