# frozen_string_literal: true

require 'rails_helper'

# The main journey. These must stay green: they catch a fix that breaks the product.
# They assert outcomes only, never details the audit fixes are expected to change.
RSpec.describe 'Critical path: assessor sets up an interview, results come back as a portfolio and fit/gap', type: :request do
  let!(:org) { create_org('acme') }

  it 'lets an assessor log in, create an assessment, and invite a candidate who can open it' do
    User.create!(email: 'assessor@acme.example', password: 'password123', role: 'admin', organization: org)
    login('assessor@acme.example', 'password123')
    expect(response).to have_http_status(:ok)
    headers = { 'Authorization' => "Bearer #{response.parsed_body['token']}", 'Content-Type' => 'application/json' }

    post '/api/v1/assessments', headers:, params: { assessment: {
      name: 'Backend Engineer', time_limit_min: 30,
      assessment_skills_attributes: [FixtureHelpers::ANCHORS.merge(skill_label: 'Negotiation', expected_level: 3, display_order: 0)]
    } }.to_json
    expect(response).to have_http_status(:created)
    assessment_id = response.parsed_body['assessment']['id']
    expect(SystemPromptGeneratorWorker.jobs.size).to eq(1)

    post "/api/v1/assessments/#{assessment_id}/sessions", headers:, params: { session: { candidate_name: 'Budi' } }.to_json
    expect(response).to have_http_status(:created)
    invite_token = response.parsed_body['session']['invite_token']
    expect(response.parsed_body['invite_url']).to end_with("/interview/#{invite_token}")

    get "/api/v1/sessions/#{invite_token}/candidate"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('role_title' => 'Backend Engineer', 'session_status' => 'pending')
  end

  it 'turns a finished interview into a portfolio and compares it to a vacancy' do
    assessment = create_assessment(org, skills: %w[Negotiation Communication])
    session = create_answered_interview(assessment)

    model = FakePortfolioModel.new(levels: { 'Negotiation' => 4, 'Communication' => 2 })
    portfolio = Portfolios::Generator.new(session:, gemini_client: model).call
    expect(portfolio.reload.generation_status).to eq('complete')

    get "/api/v1/sessions/#{session.id}/portfolio", headers: auth_headers(org)
    expect(response).to have_http_status(:ok)
    levels = response.parsed_body['portfolio']['skills'].to_h { |s| [s['skill_label'], s['ai_level']] }
    expect(levels).to eq('Negotiation' => 4, 'Communication' => 2)

    vacancy = create_vacancy(org, required: { 'Negotiation' => 3, 'Communication' => 3 })
    FitGap::Engine.new(portfolio:, vacancy:, gemini_client: FakeNarrativeModel.new).call

    get "/api/v1/portfolios/#{portfolio.id}/fitgap/#{vacancy.id}", headers: auth_headers(org)
    expect(response).to have_http_status(:ok)
    results = response.parsed_body['report']['skill_comparisons'].to_h { |c| [c['skill_label'], c['result']] }
    expect(results).to eq('Negotiation' => 'exceed', 'Communication' => 'gap')
  end
end
