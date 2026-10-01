# frozen_string_literal: true

class PortfolioSkill < ApplicationRecord
  CONFIDENCE_LEVELS = %w[high medium low].freeze

  belongs_to :portfolio
  has_one :assessor_override, dependent: :destroy

  validates :skill_label, presence: true
  # No level means "not assessed": the interview gave no evidence for this skill (audit F28).
  validates :ai_level, numericality: { only_integer: true, in: 1..5 }, allow_nil: true
  validates :ai_confidence, inclusion: { in: CONFIDENCE_LEVELS }, if: :assessed?
  validates :competency_summary, presence: true

  def assessed? = ai_level.present?

  # No tenant_id of its own: the company comes from portfolio -> session (audit F2).
  scope :for_tenant, ->(tenant_id) { where(portfolio_id: Portfolio.for_tenant(tenant_id).select(:id)) }

  # evidence is stored as JSONB array of quote strings
  def evidence_quotes
    Array(evidence)
  end
end
