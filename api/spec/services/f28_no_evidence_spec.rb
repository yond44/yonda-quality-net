# frozen_string_literal: true

require 'rails_helper'

# Audit F28: a skill with no evidence still got a level. An interview that crashed before
# anyone spoke got a "complete" portfolio with L1 for a skill nobody discussed, and when
# the AI itself tried to say "below the scale" (it answered 0), a retry turned that into
# L1. A candidate could be rejected, or passed, on a grade nobody earned. A skill without
# evidence must be recorded as "not assessed": no level, never L1.
RSpec.describe 'F28: a skill without evidence is "not assessed", never given a level', type: :request do
  let(:org) { create_org('acme') }
  let(:session) do
    create_interview_session(create_assessment(org, skills: ['Negotiation']),
                             status: 'ended', end_reason: 'error', started_at: 1.hour.ago)
  end

  def say(speaker, text) = session.transcript_turns.create!(turn_number: session.transcript_turns.count + 1, speaker:, text:)
  def generate(model) = Portfolios::Generator.new(session:, gemini_client: model).call

  it 'marks every skill "not assessed" when the candidate never answered, without asking the AI' do
    say('ai', 'Hi, thanks for joining. Tell me about a recent negotiation.')
    model = FakePortfolioModel.new(levels: { 'Negotiation' => 1 })

    generate(model)

    portfolio = session.reload.portfolio
    expect(portfolio.generation_status).to eq('complete')
    expect(portfolio.portfolio_skills.pluck(:skill_label, :ai_level)).to eq([['Negotiation', nil]])
    expect(model.prompts).to be_empty
  end

  it 'records "not assessed" when the AI says there is no evidence for a skill' do
    say('ai', 'Tell me about a recent negotiation.')
    say('candidate', "Sorry, I don't really know anything about that.")

    generate(FakePortfolioModel.new(levels: { 'Negotiation' => 'not_assessed' }))

    portfolio = session.reload.portfolio
    expect(portfolio.generation_status).to eq('complete')
    expect(portfolio.portfolio_skills.pluck(:ai_level)).to eq([nil])
  end

  it 'shows a not-assessed skill as "not assessed" in fit/gap, not as a gap' do
    say('candidate', 'Hello?')
    generate(FakePortfolioModel.new(levels: { 'Negotiation' => 'not_assessed' }))

    report = FitGap::Engine.new(portfolio: session.reload.portfolio, vacancy: create_vacancy(org),
                                gemini_client: FakeNarrativeModel.new).call

    expect(report.skill_comparisons.first).to include('result' => 'not_assessed', 'candidate_level' => nil)
  end

  it 'lets a recruiter give a not-assessed skill a level by hand' do
    say('candidate', 'Hello?')
    generate(FakePortfolioModel.new(levels: { 'Negotiation' => 'not_assessed' }))
    skill = session.reload.portfolio.portfolio_skills.first

    post "/api/v1/portfolio_skills/#{skill.id}/override", headers: auth_headers(org),
                                                           params: { override: { override_level: 3 } }.to_json

    expect(response).to have_http_status(:created)
    expect(skill.reload.assessor_override.override_level).to eq(3)
  end

  it 'still grades a skill the candidate answered (control)' do
    say('candidate', 'I renegotiated a supplier contract and cut costs by ten percent.')

    generate(FakePortfolioModel.new(levels: { 'Negotiation' => 4 }))

    expect(session.reload.portfolio.portfolio_skills.pluck(:ai_level)).to eq([4])
  end
end
