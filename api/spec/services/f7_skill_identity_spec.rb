# frozen_string_literal: true

require 'rails_helper'

# Audit F7: the portfolio stored whatever skill name the AI wrote back, and fit/gap
# then matched skills to the vacancy by exact name. A model that paraphrases a name,
# or leaves a skill out, silently turned an assessed skill into "not assessed" or
# made it disappear. Skills must be tied to the assessment's own configuration.
#
# The fake model follows the prompt like a real one would: it answers with the ID
# the prompt gives for each skill, but words the name its own way.
RSpec.describe 'F7: portfolio skills stay tied to the configured skills, whatever the AI calls them', type: :service do
  let(:org) { create_org('acme') }
  let(:session) do
    create_interview_session(create_assessment(org, skills: ['Negotiation Skills', 'Communication']),
                             status: 'ended', end_reason: 'all_covered')
  end
  let(:paraphrase) { ->(label) { label.sub(' Skills', '') } } # "Negotiation Skills" -> "Negotiation"

  it 'stores each skill under its configured name, not the AI\'s wording' do
    model = FakePortfolioModel.new(levels: { 'Negotiation Skills' => 4, 'Communication' => 3 }, rename: paraphrase)
    Portfolios::Generator.new(session:, gemini_client: model).call

    expect(session.portfolio.portfolio_skills.where(is_discovered: false).pluck(:skill_label))
      .to match_array(['Negotiation Skills', 'Communication'])
  end

  it 'lets fit/gap compare the skill instead of reporting it "not assessed"' do
    model = FakePortfolioModel.new(levels: { 'Negotiation Skills' => 4, 'Communication' => 3 }, rename: paraphrase)
    portfolio = Portfolios::Generator.new(session:, gemini_client: model).call
    vacancy = create_vacancy(org, required: { 'Negotiation Skills' => 3 })

    report = FitGap::Engine.new(portfolio:, vacancy:, gemini_client: FakeNarrativeModel.new).call

    expect(report.skill_comparisons.first['result']).to eq('exceed')
  end

  it 'does not silently drop a configured skill the AI left out' do
    model = FakePortfolioModel.new(levels: { 'Negotiation Skills' => 4 }, omit: ['Communication'])

    expect { Portfolios::Generator.new(session:, gemini_client: model).call }.to raise_error(StandardError)
    portfolio = session.reload.portfolio
    expect(portfolio.generation_status).to eq('failed')
    expect(portfolio.generation_error).to include('Communication')
  end
end
