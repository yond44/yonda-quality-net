# frozen_string_literal: true

# Audit F6: an interview that ended before every skill was covered was recorded as
# "all_covered". It now gets its own honest reason.
#
# Postgres can't drop a value from an enum type, so this can't be rolled back.
class AddPartialCoverageEndReason < ActiveRecord::Migration[7.0]
  def up
    execute "ALTER TYPE ai_interview.end_reason ADD VALUE IF NOT EXISTS 'partial_coverage'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Postgres cannot remove a value from an enum type'
  end
end
