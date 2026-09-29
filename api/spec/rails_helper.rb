# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
require 'sidekiq/testing'

# Background jobs (portfolio generation, fit/gap, coverage) are recorded instead of
# pushed to Redis, so specs are deterministic and can assert what was enqueued.
Sidekiq::Testing.fake!

Rails.root.glob('spec/support/**/*.rb').sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Login is rate-limited by Rack::Attack (backed by Redis). Specs don't test
  # throttling, and must not depend on a running Redis.
  config.before(:suite) { Rack::Attack.enabled = false }

  # Current.tenant_id / Current.user live in RequestStore. Clear it around every
  # example so tenant state can never leak from one example into another.
  config.around do |example|
    RequestStore.clear!
    example.run
    RequestStore.clear!
  end
end
