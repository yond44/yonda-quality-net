# frozen_string_literal: true

require 'rails_helper'

# Audit F23: the company for a request is picked by the tenant middleware, which
# only reads the token when it starts with "Bearer ". The login check accepts the
# token in any form. So with "Token <jwt>" (or a bare "<jwt>"), the middleware
# falls back to the X-Tenant-Scheme header or the Referer, and a valid token from
# company A works inside company B. A token must only ever work for the company
# it was issued for, whatever the header looks like.
RSpec.describe 'F23: a login token only works for the company it was issued for', type: :request do
  let!(:company_a) { create_org('company-a') }
  let!(:company_b) { create_org('company-b') }
  let!(:b_assessment) { create_assessment(company_b, name: 'Company B confidential role') }
  let(:a_token) { token_for(company_a) }

  it "rejects company A's token sent as \"Token ...\" with company B's tenant header" do
    get '/api/v1/assessments', headers: { 'Authorization' => "Token #{a_token}", 'X-Tenant-Scheme' => 'company-b' }

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('Company B confidential role')
  end

  it "rejects company A's bare token when the Referer points at company B" do
    get '/api/v1/assessments', headers: { 'Authorization' => a_token, 'Referer' => 'https://company-b.example/assessments' }

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('Company B confidential role')
  end

  it "does not let company A's token change company B's data this way" do
    put "/api/v1/assessments/#{b_assessment.id}",
        headers: { 'Authorization' => "Token #{a_token}", 'X-Tenant-Scheme' => 'company-b',
                   'Content-Type' => 'application/json' },
        params: { assessment: { name: 'Renamed by company A' } }.to_json

    expect(response).to have_http_status(:unauthorized)
    expect(b_assessment.reload.name).to eq('Company B confidential role')
  end

  it "still accepts company A's token the normal way (control: not a blanket 401)" do
    create_assessment(company_a, name: 'Company A own role')

    get '/api/v1/assessments', headers: auth_headers(company_a)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Company A own role')
    expect(response.body).not_to include('Company B confidential role')
  end
end
