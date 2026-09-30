# frozen_string_literal: true

require 'rails_helper'

# Audit F25: when a candidate's live connection dropped, nothing ever ended the
# interview. It stayed `active` forever, so the recruiter's monitor showed it as
# "Live" hours or days later, with no end and no result. The time-limit check only
# runs while the live connection is open. An interview long past its time limit
# cannot still be live, whoever asks.
RSpec.describe 'F25: an abandoned interview is not reported as live forever', type: :request do
  let(:org) { create_org('acme') }
  let(:assessment) { create_assessment(org) } # 30-minute time limit

  it 'does not show the recruiter an interview as live hours after its time limit' do
    session = create_interview_session(assessment, status: 'active', started_at: 3.hours.ago)

    get "/api/v1/sessions/#{session.id}", headers: auth_headers(org)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('session', 'status')).not_to eq('active')
  end

  it 'does not offer the candidate a live interview hours after its time limit' do
    session = create_interview_session(assessment, status: 'active', started_at: 3.hours.ago)

    get "/api/v1/sessions/#{session.invite_token}/candidate"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['session_status']).not_to eq('active')
  end

  it 'keeps an interrupted interview resumable within its time limit (control)' do
    session = create_interview_session(assessment, status: 'active', started_at: 10.minutes.ago)

    get "/api/v1/sessions/#{session.id}", headers: auth_headers(org)
    expect(response.parsed_body.dig('session', 'status')).to eq('active')

    get "/api/v1/sessions/#{session.invite_token}/candidate"
    expect(response.parsed_body['session_status']).to eq('active')
  end
end
