# frozen_string_literal: true

class AssessorOverride < ApplicationRecord
  belongs_to :portfolio_skill

  # The AI's level at the time; missing when the AI couldn't assess the skill (audit F28).
  validates :ai_level,       numericality: { only_integer: true, in: 1..5 }, allow_nil: true
  validates :override_level, numericality: { only_integer: true, in: 1..5 }
  validates :overridden_by,  presence: true
end
