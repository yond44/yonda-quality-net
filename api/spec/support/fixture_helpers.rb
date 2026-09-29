# frozen_string_literal: true

# Builders for the domain objects the net needs. Every record gets an explicit
# tenant so specs never depend on request-scoped Current.tenant_id.
module FixtureHelpers
  ANCHORS = {
    is_custom: true, scope_include: 'scope',
    l1_anchor: 'l1', l2_anchor: 'l2', l3_anchor: 'l3', l4_anchor: 'l4', l5_anchor: 'l5'
  }.freeze

  def create_assessment(org, skills: ['Negotiation'], name: 'Role')
    Assessment.create!(
      tenant_id: org.id, created_by: 1, name:, time_limit_min: 30,
      assessment_skills_attributes: skills.each_with_index.map do |label, i|
        ANCHORS.merge(skill_label: label, expected_level: 3, display_order: i)
      end
    )
  end

  def create_interview_session(assessment, status: 'pending', **attrs)
    Session.create!(tenant_id: assessment.tenant_id, assessment:, status:, **attrs)
  end

  def create_portfolio(session, levels: { 'Negotiation' => 4 })
    portfolio = Portfolio.create!(session:, generation_status: 'complete', generated_at: Time.current)
    levels.each do |label, level|
      portfolio.portfolio_skills.create!(skill_label: label, ai_level: level, ai_confidence: 'high',
                                         evidence: ['quote'], competency_summary: "#{label} summary")
    end
    portfolio
  end

  def create_vacancy(org, required: { 'Negotiation' => 3 })
    Vacancy.create!(tenant_id: org.id, created_by: 1, role_title: 'Role',
                    vacancy_skills_attributes: required.map { |label, level| { skill_label: label, expected_level: level } })
  end

  # A signed token for an admin of `org`, as the login endpoint would issue it.
  def token_for(org, user_id: 1)
    JsonWebToken.encode({ user_id:, role: 'admin', scheme: org.scheme })
  end

  def auth_headers(org)
    { 'Authorization' => "Bearer #{token_for(org)}", 'Content-Type' => 'application/json' }
  end
end

# Stands in for Gemini. Behaves like a model that follows the prompt: it reads
# each "SKILL: <label> (<id>)" line the portfolio prompt lists and answers per skill.
#   levels: { 'Label' => level }  level the "model" returns (any JSON value)
#   rename: ->(label) { ... }     how the model words the label back (paraphrasing)
#   omit:   ['Label']             skills the model leaves out of its answer
class FakePortfolioModel
  attr_reader :prompts

  def initialize(levels:, rename: ->(label) { label }, omit: [])
    @levels = levels
    @rename = rename
    @omit = omit
    @prompts = []
  end

  def generate_content(prompt, **)
    @prompts << prompt
    skills = prompt.scan(/^\s*SKILL: (.+?) \(([^)]*)\)\s*$/)
    {
      'configured_skills' => skills.reject { |label, _| @omit.include?(label) }.map do |label, id|
        { 'skill_id' => id, 'skill_label' => @rename.call(label), 'level' => @levels.fetch(label, 3),
          'confidence' => 'medium', 'evidence' => ['quote'], 'competency_summary' => "#{label} summary" }
      end,
      'discovered_skills' => []
    }
  end
end

# Stands in for Gemini in the fit/gap narrative call.
class FakeNarrativeModel
  def generate_content(*, **)
    { 'culture_narrative' => 'culture', 'overall_narrative' => 'overall' }
  end
end

RSpec.configure { |config| config.include FixtureHelpers }
