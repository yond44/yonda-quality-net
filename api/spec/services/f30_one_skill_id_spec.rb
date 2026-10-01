# frozen_string_literal: true

require 'rails_helper'

# Audit F30: the F7 fix gives every configured skill a reference in the AI prompt
# ("SKILL: Negotiation (S12)") and maps the answer back through it. But the same prompt
# also lists the coverage data, where the same skill has a different id (its catalogue
# id, or a slug of its name). The real AI sometimes copied that id instead (seen live,
# session 11), the answer was rejected as an "unknown skill", and after the retries the
# portfolio failed. A skill must have one id in the prompt, whichever part the AI reads.
RSpec.describe 'F30: each skill has one id in the portfolio prompt', type: :service do
  let(:session) do
    create_answered_interview(create_assessment(create_org('acme'), skills: ['React / Frontend Development Core', 'Communication'])).tap do |s|
      s.coverage_maps.create!(skill_label: 'React / Frontend Development Core', state: 'covered', probe_count: 3)
      s.coverage_maps.create!(skill_label: 'Communication', state: 'partial', probe_count: 2)
    end
  end

  # Answers like the real AI did in session 11: each skill's id is taken from the
  # coverage map in the prompt, not from the reference after "SKILL:".
  let(:coverage_reading_model) do
    Class.new do
      attr_reader :prompts

      def initialize = @prompts = []

      def generate_content(prompt, **)
        @prompts << prompt
        coverage = JSON.parse(prompt[/FINAL COVERAGE MAP:\s*(\{[^\n]*\})/, 1])
        { 'configured_skills' => coverage['skills'].map do |skill|
            { 'skill_id' => skill['id'], 'skill_label' => skill['label'], 'level' => 3, 'confidence' => 'medium',
              'evidence' => ['quote'], 'competency_summary' => "#{skill['label']} summary" }
          end,
          'discovered_skills' => [] }
      end
    end.new
  end

  it 'still builds the portfolio when the AI copies the id from the coverage map' do
    Portfolios::Generator.new(session:, gemini_client: coverage_reading_model).call

    portfolio = session.reload.portfolio
    expect(portfolio.generation_status).to eq('complete')
    expect(portfolio.portfolio_skills.pluck(:skill_label, :ai_level))
      .to match_array([['React / Frontend Development Core', 3], ['Communication', 3]])
  end

  it 'gives each configured skill the same id in the skill list and in the coverage map (contract)' do
    Portfolios::Generator.new(session:, gemini_client: coverage_reading_model).call rescue nil
    prompt = coverage_reading_model.prompts.first

    skill_list_ids = prompt.scan(/^\s*SKILL: (.+?) \(([^)]*)\)\s*$/).to_h
    coverage_ids = JSON.parse(prompt[/FINAL COVERAGE MAP:\s*(\{[^\n]*\})/, 1])['skills'].to_h { |s| [s['label'], s['id']] }

    expect(coverage_ids).to eq(skill_list_ids)
  end
end
