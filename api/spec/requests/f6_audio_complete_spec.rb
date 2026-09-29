# frozen_string_literal: true

require 'rails_helper'

# Audit F6: POST /sessions/:token/audio_complete needs no login and ended ANY session
# as end_reason "all_covered", even one that never started or covered nothing.
# That stored outcome is what the hiring record says happened, so it must be true.
RSpec.describe 'F6: an interview is recorded as "all covered" only when it really was', type: :request do
  let(:assessment) { create_assessment(create_org('acme'), skills: %w[Negotiation Communication]) }

  def cover(session, states)
    states.each do |label, state|
      session.coverage_maps.create!(skill_label: label, state:, probe_count: state == 'covered' ? 3 : 1)
    end
  end

  it 'refuses to end an interview that never started' do
    session = create_interview_session(assessment, status: 'pending')

    post "/api/v1/sessions/#{session.invite_token}/audio_complete"

    expect(session.reload.status).to eq('pending')
    expect(session.end_reason).to be_nil
    expect(PortfolioGeneratorWorker.jobs).to be_empty
  end

  it 'does not record an active interview with uncovered skills as "all covered"' do
    session = create_interview_session(assessment, status: 'active', started_at: 5.minutes.ago)
    cover(session, 'Negotiation' => 'covered', 'Communication' => 'initiated')

    post "/api/v1/sessions/#{session.invite_token}/audio_complete"

    expect(session.reload.end_reason).not_to eq('all_covered')
  end

  it 'ends an interview whose skills are all covered (control: the real auto-end still works)' do
    session = create_interview_session(assessment, status: 'active', started_at: 30.minutes.ago)
    cover(session, 'Negotiation' => 'covered', 'Communication' => 'covered')

    post "/api/v1/sessions/#{session.invite_token}/audio_complete"

    expect(response).to have_http_status(:ok)
    expect(session.reload).to have_attributes(status: 'ended', end_reason: 'all_covered')
    expect(PortfolioGeneratorWorker.jobs.size).to eq(1)
  end
end
