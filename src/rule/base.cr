module Alumna
  # A Rule receives the context and returns:
  # - nil          → continue to next rule
  # - ServiceError → stop the pipeline and store the error in ctx.error
  alias Rule = Proc(RuleContext, ServiceError?)
end
