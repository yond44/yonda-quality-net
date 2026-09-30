# frozen_string_literal: true

require 'rails_helper'

# Audit F25 follow-up: when the live interview can't open, the server sent every
# failure as a non-recoverable "error", and the page showed every non-recoverable
# error as "Interview Complete". A session that really has ended must say so; any
# other failure must stay an error, so the page never shows it as a finished interview.
RSpec.describe 'F25: a failure to open the interview is never reported as a finished interview', type: :service do
  let(:server) { AudioWebSocketMiddleware.new(nil) }

  it 'tells the page a session that already ended is over' do
    expect(server.send(:open_failure_message, 'Session has ended')).to include(type: 'session_ended')
  end

  it 'reports any other failure as an error, not as an ended session' do
    message = server.send(:open_failure_message, 'Session not found')

    expect(message).to include(type: 'error', recoverable: false, message: 'Session not found')
  end
end
