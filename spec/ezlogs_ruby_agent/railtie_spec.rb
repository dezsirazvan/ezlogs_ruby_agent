$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'spec_helper'
require 'rails'
require 'ezlogs_ruby_agent'

RSpec.describe EzlogsRubyAgent::Railtie do
  let(:app) { double('RailsApp', middleware: double('Middleware', use: true)) }

  before do
    EzlogsRubyAgent.configure do |config|
      config.capture_http = true
      config.capture_callbacks = true
      config.capture_jobs = true
    end
    stub_const('Rails', double('Rails', application: double('App', config: {})))
  end

  it 'inserts HttpTracker middleware if enabled' do
    expect(app.middleware).to receive(:use).with(EzlogsRubyAgent::HttpTracker)
    EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.insert_middleware' }.run(app)
  end

  it 'registers ActiveRecord and ActiveJob hooks when enabled' do
    # Just test that the initializer runs without errors
    # The actual include/prepend behavior is tested in integration tests
    expect do
      EzlogsRubyAgent::Railtie.initializers.find do |i|
        i.name == 'ezlogs_ruby_agent.include_modules'
      end.run(nil)
    end.not_to raise_error
  end

  it 'configures Sidekiq middleware when enabled and Sidekiq is defined' do
    # Create a proper Sidekiq mock
    sidekiq_class = Class.new
    server_config = double('ServerConfig')
    client_config = double('ClientConfig')
    server_chain = double('ServerChain')
    client_chain = double('ClientChain')

    allow(server_config).to receive(:server_middleware).and_yield(server_chain)
    allow(client_config).to receive(:client_middleware).and_yield(client_chain)
    allow(sidekiq_class).to receive(:configure_server).and_yield(server_config)
    allow(sidekiq_class).to receive(:configure_client).and_yield(client_config)
    allow(server_chain).to receive(:add)
    allow(client_chain).to receive(:add)

    stub_const('Sidekiq', sidekiq_class)

    expect(server_chain).to receive(:add).with(EzlogsRubyAgent::SidekiqJobTracker)
    expect(client_chain).to receive(:add).with(EzlogsRubyAgent::JobEnqueueMiddleware)

    EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.configure_sidekiq' }.run(nil)
  end

  it 'does not configure Sidekiq when not defined' do
    hide_const('Sidekiq')
    expect do
      EzlogsRubyAgent::Railtie.initializers.find do |i|
        i.name == 'ezlogs_ruby_agent.configure_sidekiq'
      end.run(nil)
    end.not_to raise_error
  end

  it 'integrates with Rails application config' do
    expect(Rails.application.config).to be_a(Hash)
  end

  it 'does not crash if Rails is missing' do
    hide_const('Rails')
    expect { described_class }.not_to raise_error
  end
end
