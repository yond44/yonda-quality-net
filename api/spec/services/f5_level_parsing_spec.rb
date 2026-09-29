# frozen_string_literal: true

require 'rails_helper'

# Audit F5: the portfolio generator did `level.to_i.clamp(1, 5)`, so an answer of
# "L3" or no level at all was silently stored as L1 (a fake gap), and the portfolio
# was marked complete. A level must be read correctly or generation must fail loudly.
RSpec.describe 'F5: an AI level the code cannot read is never stored as L1', type: :service do
  let(:session) do
    create_interview_session(create_assessment(create_org('acme'), skills: ['Negotiation']),
                             status: 'ended', end_reason: 'all_covered')
  end

  def generate(level)
    Portfolios::Generator.new(session:, gemini_client: FakePortfolioModel.new(levels: { 'Negotiation' => level })).call
  end

  it 'reads "L3" as level 3' do
    generate('L3')

    expect(session.portfolio.portfolio_skills.pluck(:ai_level)).to eq([3])
  end

  it 'still reads a plain integer level' do
    generate(4)

    expect(session.portfolio.portfolio_skills.pluck(:ai_level)).to eq([4])
  end

  it 'fails generation loudly when there is no usable level, instead of storing L1' do
    expect { generate(nil) }.to raise_error(StandardError)

    portfolio = session.reload.portfolio
    expect(portfolio.generation_status).to eq('failed')
    expect(portfolio.generation_error).to match(/level/i)
    expect(portfolio.portfolio_skills.where(ai_level: 1)).to be_empty
  end

  it 'keeps the previous skills when a regeneration fails, instead of leaving a half-saved portfolio' do
    two_skills = create_interview_session(create_assessment(create_org('beta'), skills: %w[Negotiation Communication]),
                                          status: 'ended', end_reason: 'all_covered')
    first_run = FakePortfolioModel.new(levels: { 'Negotiation' => 4, 'Communication' => 3 })
    Portfolios::Generator.new(session: two_skills, gemini_client: first_run).call

    broken_run = FakePortfolioModel.new(levels: { 'Negotiation' => 2, 'Communication' => nil })
    expect { Portfolios::Generator.new(session: two_skills, gemini_client: broken_run).call }.to raise_error(StandardError)

    portfolio = two_skills.reload.portfolio
    expect(portfolio.generation_status).to eq('failed')
    expect(portfolio.portfolio_skills.pluck(:skill_label, :ai_level)).to match_array([['Negotiation', 4], ['Communication', 3]])
  end
end
