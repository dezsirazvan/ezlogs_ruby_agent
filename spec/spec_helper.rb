require "ezlogs_ruby_agent"
require 'simplecov'
require 'rspec'
require 'timecop'
require 'webmock/rspec'

# Start SimpleCov for test coverage
SimpleCov.start do
  add_filter "/spec/"
  minimum_coverage 100
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Clean up threads and reset configuration between tests
  config.before(:each) do
    # Reset the global configuration
    EzlogsRubyAgent.instance_variable_set(:@config, nil)
    EzlogsRubyAgent.instance_variable_set(:@writer, nil)
    EzlogsRubyAgent.instance_variable_set(:@delivery_engine, nil)
    EzlogsRubyAgent.instance_variable_set(:@processor, nil)

    # Clear any correlation context
    Thread.current[:correlation_id] = nil
    Thread.current[:ezlogs_context] = nil
  end

  config.after(:each) do
    # Clean up any background threads
    if defined?(EzlogsRubyAgent::EventWriter) && EzlogsRubyAgent.instance_variable_get(:@writer)
      writer = EzlogsRubyAgent.instance_variable_get(:@writer)
      writer.instance_variable_get(:@writer)&.kill if writer.instance_variable_get(:@writer)&.alive?
    end

    # Clean up delivery engine
    if defined?(EzlogsRubyAgent::DeliveryEngine) && EzlogsRubyAgent.instance_variable_get(:@delivery_engine)
      engine = EzlogsRubyAgent.instance_variable_get(:@delivery_engine)
      engine.shutdown
    end

    Timecop.return
  end
end
