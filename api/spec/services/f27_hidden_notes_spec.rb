# frozen_string_literal: true

require 'rails_helper'

# Audit F27: during the interview the app sends the AI hidden notes (which skills are
# covered, what to ask next). The AI's instructions say to keep messages starting with
# "[COVERAGE MAP" silent, but the app sent them as "[COVERAGE_MAP]", so the rule
# described a tag the AI never received. In a live test the AI's speech began with
# "[COVERAGE_MAP]". A text filter then removed such echoes from the transcript without
# a trace, so the recruiter never learned the candidate may have heard internal notes.
RSpec.describe 'F27: the AI keeps its hidden notes silent, and a slip is visible to the recruiter', type: :service do
  let(:session) do
    session = create_interview_session(create_assessment(create_org('acme')), status: 'active', started_at: 1.minute.ago)
    session.coverage_maps.create!(skill_label: 'Negotiation', state: 'not_yet', probe_count: 0)
    session
  end
  let(:server) { AudioWebSocketMiddleware.new(nil) }

  it 'sends the hidden notes under the tag the AI is told to keep silent about (contract)' do
    instructions = Assessments::SystemPromptCompiler.new(session.assessment).call
    silent_tag = instructions[/These messages start with "([^"]+)"/, 1] or raise 'tag not found in the AI instructions'

    expect(Coverage::MapInjector.new(session).injection_text).to start_with(silent_tag)
  end

  it 'marks the recruiter transcript when the AI read internal notes aloud, instead of hiding it' do
    said = '[COVERAGE_MAP] That is a very hands-off approach to development.'

    transcript = server.send(:recruiter_transcript_text, said)

    expect(transcript).to include('That is a very hands-off approach to development.')
    expect(transcript).not_to include('[COVERAGE_MAP]')
    expect(transcript).to match(/internal notes/i)
  end

  it 'leaves a normal answer unchanged (control)' do
    said = 'Tell me about the hardest bug you fixed last year.'

    expect(server.send(:sanitize_output_transcription, said)).to eq(said)
  end
end
