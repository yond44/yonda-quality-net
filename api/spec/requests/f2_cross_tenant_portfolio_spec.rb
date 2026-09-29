# frozen_string_literal: true

require 'rails_helper'

# Audit F2: portfolios, portfolio skills and fit/gap reports have no tenant column and
# were loaded by bare ID, so any company's assessor could read AND change another
# company's candidate data. Every request below uses company A's valid token on
# company B's records and must behave as if the record does not exist (404),
# without reading or changing anything.
RSpec.describe "F2: one company cannot read or change another company's candidate data", type: :request do
  let!(:company_a) { create_org('company-a') }
  let!(:company_b) { create_org('company-b') }

  let!(:b_portfolio) do
    session = create_interview_session(create_assessment(company_b), status: 'ended', end_reason: 'all_covered')
    create_portfolio(session, levels: { 'Negotiation' => 4 })
  end
  let(:b_skill)   { b_portfolio.portfolio_skills.first }
  let!(:a_vacancy) { create_vacancy(company_a) }

  it 'does not export company B\'s portfolio to company A' do
    get "/api/v1/portfolios/#{b_portfolio.id}/export", params: { format: 'json' }, headers: auth_headers(company_a)

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Negotiation summary')
  end

  it 'does not let company A override company B\'s rating' do
    post "/api/v1/portfolio_skills/#{b_skill.id}/override", headers: auth_headers(company_a),
                                                             params: { override: { override_level: 1 } }.to_json

    expect(response).to have_http_status(:not_found)
    expect(b_skill.reload.assessor_override).to be_nil
  end

  it 'does not let company A generate a fit/gap report on company B\'s candidate' do
    post "/api/v1/portfolios/#{b_portfolio.id}/fitgap", headers: auth_headers(company_a),
                                                         params: { fitgap: { vacancy_id: a_vacancy.id } }.to_json

    expect(response).to have_http_status(:not_found)
    expect(FitGapGeneratorWorker.jobs).to be_empty
  end

  it 'does not show or regenerate company B\'s existing fit/gap report to company A' do
    b_vacancy = create_vacancy(company_b)
    report = FitGap::Engine.new(portfolio: b_portfolio, vacancy: b_vacancy, gemini_client: FakeNarrativeModel.new).call

    get "/api/v1/portfolios/#{b_portfolio.id}/fitgap/#{b_vacancy.id}", headers: auth_headers(company_a)
    expect(response).to have_http_status(:not_found)

    post "/api/v1/portfolios/#{b_portfolio.id}/regenerate_fitgap", headers: auth_headers(company_a),
                                                                    params: { vacancy_id: a_vacancy.id }.to_json
    expect(response).to have_http_status(:not_found)
    expect(FitGapReport.exists?(report.id)).to be(true)
  end

  it 'still serves company B its own portfolio (control: isolation is not a blanket 404)' do
    get "/api/v1/portfolios/#{b_portfolio.id}/export", params: { format: 'json' }, headers: auth_headers(company_b)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Negotiation summary')
  end
end
