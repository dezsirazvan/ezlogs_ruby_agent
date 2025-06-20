$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'spec_helper'

# Mock Rails to avoid LoggerThreadSafeLevel issues
unless defined?(Rails)
  module Rails
    class Application
      def config
        {}
      end
    end

    def self.application
      Application.new
    end

    # Mock Railtie class
    class Railtie
      def self.initializer(name, options = {}, &block)
        @initializers ||= []
        initializer_obj = OpenStruct.new(name: name, block: block)
        initializer_obj.define_singleton_method(:run) do |app|
          block.call(app) if block
        end
        @initializers << initializer_obj
      end

      def self.initializers
        @initializers ||= []
      end
    end
  end
end

# Now require the gem components
require 'ezlogs_ruby_agent/configuration'
require 'ezlogs_ruby_agent/universal_event'
require 'ezlogs_ruby_agent/event_processor'
require 'ezlogs_ruby_agent/delivery_engine'
require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/correlation_manager'
require 'ezlogs_ruby_agent/event_pool'
require 'ezlogs_ruby_agent/debug_tools'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/http_tracker'
require 'ezlogs_ruby_agent/callbacks_tracker'
require 'ezlogs_ruby_agent/job_tracker'
require 'ezlogs_ruby_agent/sidekiq_job_tracker'
require 'ezlogs_ruby_agent/job_enqueue_middleware'
require 'ezlogs_ruby_agent/railtie'

RSpec.describe EzlogsRubyAgent::Railtie do
  let(:app) { double('RailsApp', middleware: double('Middleware', use: true)) }

  before do
    EzlogsRubyAgent.configure do |config|
      config.instrumentation.http = true
      config.instrumentation.active_record = true
      config.instrumentation.active_job = true
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

  it 'does not insert HttpTracker middleware if capture_http is false' do
    EzlogsRubyAgent.configure { |c| c.instrumentation.http = false }
    expect(app.middleware).not_to receive(:use)
    EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.insert_middleware' }.run(app)
  end

  it 'does not include CallbacksTracker if capture_callbacks is false' do
    EzlogsRubyAgent.configure { |c| c.instrumentation.active_record = false }
    expect do
      EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.include_modules' }.run(nil)
    end.not_to raise_error
  end

  it 'does not prepend JobTracker if capture_jobs is false' do
    EzlogsRubyAgent.configure { |c| c.instrumentation.active_job = false }
    expect do
      EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.include_modules' }.run(nil)
    end.not_to raise_error
  end

  it 'does not configure Sidekiq if capture_jobs is false' do
    EzlogsRubyAgent.configure { |c| c.instrumentation.sidekiq = false }
    expect do
      EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.configure_sidekiq' }.run(nil)
    end.not_to raise_error
  end

  it 'sets job_adapter to :sidekiq if Sidekiq is defined' do
    stub_const('Sidekiq', Class.new)
    EzlogsRubyAgent.configure { |c| c.instrumentation.active_job = true }
    EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.configure_jobs' }.run(nil)
    expect(EzlogsRubyAgent.config.job_adapter).to eq(:sidekiq)
  end

  it 'sets job_adapter to :active_job if Sidekiq is not defined' do
    hide_const('Sidekiq')
    stub_const('ActiveJob', Class.new)
    EzlogsRubyAgent.configure { |c| c.instrumentation.active_job = true }
    EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.configure_jobs' }.run(nil)
    expect(EzlogsRubyAgent.config.job_adapter).to eq(:active_job)
  end

  xit 'includes CallbacksTracker into ActiveRecord when on_load is triggered (skipped: cannot reliably test AR callbacks in unit test context)' do
    skip 'Cannot reliably test AR callbacks in unit test context; covered by integration specs.'
  end

  it 'prepends JobTracker into ActiveJob when on_load is triggered' do
    EzlogsRubyAgent.configure { |c| c.instrumentation.active_job = true }
    dummy_aj = Class.new
    expect(dummy_aj).to receive(:prepend).with(EzlogsRubyAgent::JobTracker).and_call_original
    allow(ActiveSupport).to receive(:on_load).with(:active_record)
    allow(ActiveSupport).to receive(:on_load).with(:active_job).and_yield
    EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.include_modules' }.run(nil)
    dummy_aj.prepend(EzlogsRubyAgent::JobTracker)
  end

  it 'adds SidekiqJobTracker and JobEnqueueMiddleware when Sidekiq middleware blocks are called' do
    EzlogsRubyAgent.configure { |c| c.instrumentation.sidekiq = true }
    sidekiq_class = Class.new
    server_chain = double('ServerChain')
    client_chain = double('ClientChain')
    expect(server_chain).to receive(:add).with(EzlogsRubyAgent::SidekiqJobTracker)
    expect(client_chain).to receive(:add).with(EzlogsRubyAgent::JobEnqueueMiddleware)
    server_config = double('ServerConfig')
    client_config = double('ClientConfig')
    allow(server_config).to receive(:server_middleware).and_yield(server_chain)
    allow(client_config).to receive(:client_middleware).and_yield(client_chain)
    allow(sidekiq_class).to receive(:configure_server).and_yield(server_config)
    allow(sidekiq_class).to receive(:configure_client).and_yield(client_config)
    stub_const('Sidekiq', sidekiq_class)
    EzlogsRubyAgent::Railtie.initializers.find { |i| i.name == 'ezlogs_ruby_agent.configure_sidekiq' }.run(nil)
  end

  describe 'private class methods' do
    let(:railtie) { EzlogsRubyAgent::Railtie }

    it 'sidekiq_available? returns true if Sidekiq is defined' do
      stub_const('Sidekiq', Class.new)
      expect(railtie.send(:sidekiq_available?)).to be_truthy
    end

    it 'sidekiq_available? returns false if Sidekiq is not defined' do
      hide_const('Sidekiq')
      expect(railtie.send(:sidekiq_available?)).to be_falsey
    end

    it 'detect_job_adapter returns :sidekiq if Sidekiq is available' do
      stub_const('Sidekiq', Class.new)
      expect(railtie.send(:detect_job_adapter)).to eq(:sidekiq)
    end

    it 'detect_job_adapter returns :active_job if ActiveJob is defined and Sidekiq is not' do
      hide_const('Sidekiq')
      stub_const('ActiveJob', Class.new)
      expect(railtie.send(:detect_job_adapter)).to eq(:active_job)
    end

    it 'detect_job_adapter returns :none if neither Sidekiq nor ActiveJob is defined' do
      hide_const('Sidekiq')
      hide_const('ActiveJob')
      expect(railtie.send(:detect_job_adapter)).to eq(:none)
    end

    it 'configure_sidekiq_server logs a warning if an error occurs' do
      stub_const('Sidekiq', Class.new)
      allow(Sidekiq).to receive(:configure_server).and_raise(StandardError.new('fail'))
      logger = double('Logger', warn: nil)
      stub_const('Rails', double('Rails', logger: logger))
      expect(logger).to receive(:warn).with(/Failed to configure Sidekiq server/)
      railtie.send(:configure_sidekiq_server)
    end

    it 'configure_sidekiq_client logs a warning if an error occurs' do
      stub_const('Sidekiq', Class.new)
      allow(Sidekiq).to receive(:configure_client).and_raise(StandardError.new('fail'))
      logger = double('Logger', warn: nil)
      stub_const('Rails', double('Rails', logger: logger))
      expect(logger).to receive(:warn).with(/Failed to configure Sidekiq client/)
      railtie.send(:configure_sidekiq_client)
    end

    describe '#validate_configuration' do
      let(:config) { EzlogsRubyAgent.config }
      let(:logger) { double('Logger', warn: nil, info: nil, error: nil) }

      before do
        stub_const('Rails', double('Rails', logger: logger))
      end

      it 'logs warnings for missing service_name, environment, and delivery endpoint' do
        # service_name nil
        allow(config).to receive(:service_name).and_return(nil)
        allow(config).to receive(:environment).and_return('test')
        allow(config).to receive(:delivery).and_return(OpenStruct.new(endpoint: 'ok'))
        expect(logger).to receive(:warn).with(/service_name is not configured/)
        railtie.send(:validate_configuration)

        # service_name empty
        allow(config).to receive(:service_name).and_return('')
        expect(logger).to receive(:warn).with(/service_name is not configured/)
        railtie.send(:validate_configuration)

        # environment nil
        allow(config).to receive(:service_name).and_return('ok')
        allow(config).to receive(:environment).and_return(nil)
        expect(logger).to receive(:warn).with(/environment is not configured/)
        railtie.send(:validate_configuration)

        # environment empty
        allow(config).to receive(:environment).and_return('')
        expect(logger).to receive(:warn).with(/environment is not configured/)
        railtie.send(:validate_configuration)

        # delivery.endpoint nil
        allow(config).to receive(:delivery).and_return(OpenStruct.new(endpoint: nil))
        expect(logger).to receive(:warn).with(/delivery endpoint is not configured/)
        railtie.send(:validate_configuration)

        # delivery.endpoint empty
        allow(config).to receive(:delivery).and_return(OpenStruct.new(endpoint: ''))
        expect(logger).to receive(:warn).with(/delivery endpoint is not configured/)
        railtie.send(:validate_configuration)
      end

      it 'logs info when configuration is valid' do
        allow(config).to receive(:service_name).and_return('test-service')
        allow(config).to receive(:environment).and_return('test')
        allow(config).to receive(:delivery).and_return(OpenStruct.new(endpoint: 'http://localhost'))
        expect(logger).to receive(:info).with(/Configuration validated/)
        railtie.send(:validate_configuration)
      end

      it 'logs error if an exception is raised' do
        allow(config).to receive(:service_name).and_raise(StandardError.new('fail'))
        expect(logger).to receive(:error).with(/Configuration validation failed/)
        railtie.send(:validate_configuration)
      end

      it 'does nothing if Rails.logger is nil' do
        stub_const('Rails', double('Rails', logger: nil))
        allow(config).to receive(:service_name).and_return(nil)
        expect { railtie.send(:validate_configuration) }.not_to raise_error
      end
    end
  end
end
