# frozen_string_literal: true

require 'rails_helper'

# Audit F3: invite links were built from APP_BASE_URL (the backend), so candidates
# got a 404. The link must point at the web app, on a route the web app serves.
RSpec.describe 'F3: the candidate invite link opens the web app', type: :model do
  around do |example|
    saved = ENV.to_h.slice('APP_BASE_URL', 'WEB_BASE_URL')
    ENV['APP_BASE_URL'] = 'https://api.example.test'
    ENV['WEB_BASE_URL'] = 'https://app.example.test'
    example.run
  ensure
    %w[APP_BASE_URL WEB_BASE_URL].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  let(:session) { create_interview_session(create_assessment(create_org('acme'))) }

  it 'points at the web app, not the backend' do
    expect(session.invite_url).to eq("https://app.example.test/interview/#{session.invite_token}")
  end

  it 'uses a path the web app actually routes (cross-service contract)' do
    web_routes = File.read(Rails.root.join('../web/src/App.tsx'))
    path_template = URI(session.invite_url).path.sub(session.invite_token, ':token')

    expect(web_routes).to include(%(path="#{path_template}")),
                          "web/src/App.tsx has no route for #{path_template}"
  end
end
