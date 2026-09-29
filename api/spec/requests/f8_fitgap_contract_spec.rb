# frozen_string_literal: true

require 'rails_helper'

# Audit F8: the API sent `expected_level` while the web read `required_level`, so the
# fit/gap "Required" column was always blank (and the override marker never showed).
# This is a contract test: the field list comes from the web app's own TypeScript
# type, so renaming a field on EITHER side breaks the build.
RSpec.describe 'F8: the fit/gap payload matches the fields the web app reads', type: :request do
  let(:web_fields) do
    source = File.read(Rails.root.join('../web/src/types/index.ts'))
    body = source[/export interface SkillComparison \{(.*?)\}/m, 1] or raise 'SkillComparison type not found in web/src/types/index.ts'
    body.scan(/^\s*(\w+)(\??):/).map { |name, optional| { name:, required: optional.empty? } }
  end

  let(:org) { create_org('acme') }
  let(:portfolio) do
    session = create_interview_session(create_assessment(org), status: 'ended', end_reason: 'all_covered')
    create_portfolio(session, levels: { 'Negotiation' => 4 })
  end
  let(:vacancy) { create_vacancy(org, required: { 'Negotiation' => 3 }) }

  def fetch_comparison
    FitGap::Engine.new(portfolio:, vacancy:, gemini_client: FakeNarrativeModel.new).call
    get "/api/v1/portfolios/#{portfolio.id}/fitgap/#{vacancy.id}", headers: auth_headers(org)
    expect(response).to have_http_status(:ok)
    response.parsed_body['report']['skill_comparisons'].first
  end

  it 'sends every field the web type marks as required' do
    comparison = fetch_comparison

    missing = web_fields.select { |f| f[:required] }.map { |f| f[:name] } - comparison.keys
    expect(missing).to be_empty, "web reads #{missing.join(', ')} but the API does not send it"
  end

  it 'fills the Required column with the vacancy\'s level' do
    expect(fetch_comparison['required_level']).to eq(3)
  end

  it 'marks a comparison that uses a human override' do
    portfolio.portfolio_skills.first.create_assessor_override!(ai_level: 4, override_level: 3, overridden_by: 1)

    expect(fetch_comparison).to include('candidate_level' => 3, 'is_override' => true)
  end
end
