# frozen_string_literal: true

require 'rails_helper'

# Audit F32: the PDF export crashed (500) for every portfolio a recruiter had overridden,
# because the override line contains "→", which the PDF's built-in font can't encode
# (Windows-1252). Any AI text with such a character (evidence quotes, narratives) crashed
# it the same way. The web's PDF button then did nothing, with no message.
RSpec.describe 'F32: the portfolio PDF export works for every portfolio', type: :request do
  let(:org) { create_org('acme') }
  let(:portfolio) { create_portfolio(create_answered_interview(create_assessment(org)), levels: { 'Negotiation' => 2 }) }

  def export_pdf
    get "/api/v1/portfolios/#{portfolio.id}/export", params: { format: 'pdf' }, headers: auth_headers(org)
  end

  def expect_a_pdf
    expect(response).to have_http_status(:ok)
    expect(response.body.byteslice(0, 4)).to eq('%PDF')
  end

  it 'exports a PDF for a portfolio whose level a recruiter overrode' do
    portfolio.portfolio_skills.first.create_assessor_override!(
      ai_level: 2, override_level: 4, overridden_by: 1, overridden_at: Time.current, assessor_notes: 'Strong follow-up'
    )

    export_pdf

    expect_a_pdf
  end

  it "exports a PDF when the AI's evidence contains symbols outside basic Latin" do
    portfolio.portfolio_skills.first.update!(evidence: ['Cut load time from 3s → 1s', 'Served ≥ 10k users'])

    export_pdf

    expect_a_pdf
  end

  it 'still exports a PDF for a plain portfolio (control)' do
    export_pdf

    expect_a_pdf
  end
end
