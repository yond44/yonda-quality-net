# frozen_string_literal: true

# Audit F28: every portfolio skill had to have a level 1-5, so a skill with no
# evidence was given one anyway (usually L1). A missing level now means
# "not assessed". The existing 1-5 checks stay: they pass for a missing value.
class AllowNotAssessedSkills < ActiveRecord::Migration[7.0]
  def change
    change_column_null :portfolio_skills, :ai_level, true
    change_column_null :portfolio_skills, :ai_confidence, true
    # An override keeps a copy of the AI's level, which may now be "not assessed".
    change_column_null :assessor_overrides, :ai_level, true
  end
end
