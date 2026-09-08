require "./session/store"
require "./session/memory_store"
require "./session/cookie"
require "./session/handler"

module Alumna
  def self.session(
    store : SessionStore,
    cookie : String = Session::DEFAULT_COOKIE,
    store_key : String = Session::DEFAULT_STORE_KEY,
    required : Bool = true,
    skip_providers : Array(String) = Session::DEFAULT_SKIP,
    http_only : Bool = true,
    secure : Bool = false,
    same_site : Symbol = :lax,
    path : String = "/",
    domain : String? = nil,
  ) : Rule
    Session.new(
      store,
      cookie: cookie,
      store_key: store_key,
      required: required,
      skip_providers: skip_providers,
      http_only: http_only,
      secure: secure,
      same_site: same_site,
      path: path,
      domain: domain,
    ).rule
  end
end
