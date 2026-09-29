# frozen_string_literal: true

# Audit F1 / M2: users had no tenant, so login let the client choose one.
# Each user now belongs to exactly one organization; login issues tokens only
# for that organization.
#
# Nullable on purpose: existing users can't be safely auto-assigned, so they stay
# unassigned (and cannot log in) until an operator sets their organization.
#
# No DB foreign key: `organizations` lives in the public schema and is owned by
# the upstream platform in production (same convention as every tenant_id here).
class AddOrganizationToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :organization_id, :bigint
    add_index  :users, :organization_id
  end
end
