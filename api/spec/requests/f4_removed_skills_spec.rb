# frozen_string_literal: true

require 'rails_helper'

# Audit F4: the edit forms send the full list of skills the assessor wants to keep.
# The API only deleted rows explicitly marked `_destroy`, so a skill the assessor
# removed silently stayed (and the candidate was still interviewed on it).
# The payloads below are exactly what the edit pages send after removing a skill.
RSpec.describe 'F4: a skill removed in the edit form is really removed', type: :request do
  let!(:org) { create_org('acme') }

  it 'removes an assessment skill that is left out of the saved list' do
    assessment = create_assessment(org, skills: ['Keep Me', 'Remove Me'])
    kept = assessment.assessment_skills.find_by!(skill_label: 'Keep Me')

    put "/api/v1/assessments/#{assessment.id}", headers: auth_headers(org), params: { assessment: {
      name: assessment.name, time_limit_min: 30,
      assessment_skills_attributes: [kept.attributes.slice(*%w[id skill_label is_custom scope_include l1_anchor l2_anchor
                                                                l3_anchor l4_anchor l5_anchor expected_level display_order])]
    } }.to_json

    expect(response).to have_http_status(:ok)
    expect(assessment.assessment_skills.reload.pluck(:skill_label)).to eq(['Keep Me'])
  end

  it 'removes a vacancy skill that is left out of the saved list' do
    vacancy = create_vacancy(org, required: { 'Keep Me' => 3, 'Remove Me' => 4 })
    kept = vacancy.vacancy_skills.find_by!(skill_label: 'Keep Me')

    put "/api/v1/vacancies/#{vacancy.id}", headers: auth_headers(org), params: { vacancy: {
      role_title: vacancy.role_title, culture_dimensions: '', competency_expectations: '',
      vacancy_skills_attributes: [{ id: kept.id, skill_label: 'Keep Me', expected_level: 3 }]
    } }.to_json

    expect(response).to have_http_status(:ok)
    expect(vacancy.vacancy_skills.reload.pluck(:skill_label)).to eq(['Keep Me'])
  end
end
