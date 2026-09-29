# frozen_string_literal: true

# Helpers for building multi-tenant fixtures. A "tenant" is an Organization row;
# its `scheme` is what ends up in the JWT and selects the tenant per request.
module TenantHelpers
  def create_org(scheme)
    Organization.create!(name: scheme.titleize, scheme: scheme, identifier: scheme, host: "#{scheme}.example")
  end

  def login(email, password, headers: {})
    post '/api/v1/auth/login', params: { email:, password: }.to_json,
                               headers: { 'Content-Type' => 'application/json' }.merge(headers)
  end

  def token_scheme(token)
    JsonWebToken.decode(token)[:scheme]
  end
end

RSpec.configure { |config| config.include TenantHelpers }
