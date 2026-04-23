Alumna::Formats.register("email", "must be a valid email address") do |v|
  v.size <= 254 && v.count('@') == 1 && v.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
end
