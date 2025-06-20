# Load the gem
require "ezlogs_ruby_agent"
require 'json'
require 'active_support/json'
require 'active_support/core_ext/object/json'
require 'simplecov'
require 'climate_control'
# require 'rspec' # Not needed, handled by rspec-rails
require 'timecop'
require 'webmock/rspec'

# Start SimpleCov for test coverage
SimpleCov.start do
  add_filter "/spec/"
  minimum_coverage 80
end

# Custom matchers for testing
RSpec::Matchers.define :have_event_count do |expected_count|
  match do |events|
    events&.length == expected_count
  end

  failure_message do |events|
    "expected #{expected_count} events, got #{events&.length || 0}"
  end
end

RSpec::Matchers.define :be_nil_or_empty do
  match do |actual|
    actual.nil? || actual.empty?
  end

  failure_message do |actual|
    "expected #{actual.inspect} to be nil or empty"
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Clean up between tests
  config.before(:each) do
    # Clear thread-local storage
    Thread.current[:current_user] = nil
    Thread.current[:ezlogs_context] = nil

    # Reset EzlogsRubyAgent configuration
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
      config.instrumentation.http_requests = true
      config.instrumentation.active_record = true
      config.instrumentation.active_job = true
      config.included_resources = []
      config.excluded_resources = []
      # config.actor_extractor = nil # Remove or update if needed
    end

    # Clear any captured events
    EzlogsRubyAgent::DebugTools.clear_captured_events if defined?(EzlogsRubyAgent::DebugTools)
  end

  config.after(:each) do
    # Clean up thread-local storage
    Thread.current[:current_user] = nil
    Thread.current[:ezlogs_context] = nil

    # Clear any captured events
    EzlogsRubyAgent::DebugTools.clear_captured_events if defined?(EzlogsRubyAgent::DebugTools)
  end

  # Mock time for consistent testing
  config.before(:each) do
    Timecop.freeze(Time.utc(2025, 6, 19, 23, 0, 0))
  end

  config.after(:each) do
    Timecop.return
  end
end
