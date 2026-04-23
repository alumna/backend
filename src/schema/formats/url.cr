require "uri"

Alumna::Formats.register("url", "must be a valid URL (http or https)") do |v|
  s = v.strip
  next false if s.empty? || s.includes?(' ')
  uri = URI.parse(s) rescue nil
  !!(uri && (uri.scheme == "http" || uri.scheme == "https") && !uri.host.to_s.empty?)
end
