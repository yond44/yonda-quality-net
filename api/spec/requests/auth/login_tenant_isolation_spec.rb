# frozen_string_literal: true

require 'rails_helper'

# Audit F1 — login must only ever issue a token for the user's OWN company.
# Before the fix, the tenant came from a client-supplied header or from
# "whichever organization row is first", and users had no company at all.
RSpec.describe 'F1: login issues tokens only for the user\'s own tenant', type: :request do
  # Other company created FIRST: the old code falls back to the first row.
  let!(:other_corp) { create_org('other-corp') }
  let!(:own_corp)   { create_org('own-corp') }

  let(:password) { 'password123' }
  let!(:user) do
    u = User.create!(email: 'assessor@own-corp.example', password:, role: 'admin')
    # Users gain a company in the fix; before it the column doesn't exist, so the
    # examples below run against the old behaviour and fail on their assertions.
    u.update!(organization: own_corp) if u.has_attribute?(:organization_id)
    u
  end

  it 'issues a token for the user\'s own company when no tenant header is sent (web login)' do
    login(user.email, password)

    expect(response).to have_http_status(:ok)
    expect(token_scheme(response.parsed_body['token'])).to eq('own-corp')
  end

  it 'ignores an X-Tenant-Scheme header that names another company' do
    login(user.email, password, headers: { 'X-Tenant-Scheme' => 'other-corp' })

    expect(response).to have_http_status(:ok)
    expect(token_scheme(response.parsed_body['token'])).to eq('own-corp')
  end

  it 'does not let the issued token read another company\'s assessments' do
    Assessment.create!(tenant_id: other_corp.id, created_by: 999, name: 'Other Corp Secret Role', time_limit_min: 30)

    login(user.email, password, headers: { 'X-Tenant-Scheme' => 'other-corp' })
    token = response.parsed_body['token']
    get '/api/v1/assessments', headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    names = response.parsed_body['assessments'].map { |a| a['name'] }
    expect(names).not_to include('Other Corp Secret Role')
  end

  it 'refuses to log in a user who belongs to no company' do
    orphan = User.create!(email: 'orphan@example.com', password:, role: 'admin')

    login(orphan.email, password)

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['token']).to be_nil
  end
end
