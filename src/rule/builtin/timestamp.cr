module Alumna
  # Injects the current UTC timestamp into the specified fields of `ctx.data`.
  # Designed to be used with explicit method scopes (e.g., `on: :create` or `on: :write`).
  def self.timestamp(*fields : String) : Rule
    Rule.new do |ctx|
      now = Time.utc
      fields.each { |f| ctx.data[f] = now }
      nil
    end
  end
end
