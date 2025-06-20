require 'spec_helper'

RSpec.describe EzlogsRubyAgent::Configuration do
  let(:config) { described_class.new }

  describe 'configuration validation' do
    it 'validates required fields' do
      config.service_name = nil
      expect { config.validate! }.to raise_error(EzlogsRubyAgent::ConfigurationError, /Service name is required/)
      config.service_name = 'my-app'
      config.environment = nil
      expect { config.validate! }.to raise_error(EzlogsRubyAgent::ConfigurationError, /Environment is required/)
    end

    it 'validates endpoint format' do
      config.delivery.endpoint = 'ftp://example.com'
      expect { config.validate! }.to raise_error(EzlogsRubyAgent::ConfigurationError, /endpoint must be a valid URL/)
      config.delivery.endpoint = 'http://example.com'
      expect { config.validate! }.not_to raise_error
    end

    it 'validates timeout and batch size' do
      config.delivery.timeout = 0
      expect { config.validate! }.to raise_error(EzlogsRubyAgent::ConfigurationError, /timeout must be positive/)
      config.delivery.timeout = 61
      expect do
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError, /timeout cannot exceed 60 seconds/)
      config.delivery.timeout = 30
      config.delivery.batch_size = 0
      expect { config.validate! }.to raise_error(EzlogsRubyAgent::ConfigurationError, /batch_size must be positive/)
    end

    it 'validates performance sample rate' do
      config.performance.sample_rate = -0.1
      expect { config.validate! }.to raise_error(EzlogsRubyAgent::ConfigurationError, /sample_rate must be between/)
      config.performance.sample_rate = 1.1
      expect { config.validate! }.to raise_error(EzlogsRubyAgent::ConfigurationError, /sample_rate must be between/)
      config.performance.sample_rate = 1.0
      expect { config.validate! }.not_to raise_error
    end
  end

  describe 'detection and fallbacks' do
    it 'detects service name from ENV' do
      ClimateControl.modify(EZLOGS_SERVICE_NAME: 'env-service') do
        expect(described_class.new.service_name).to eq('env-service')
      end
    end

    it 'falls back to unknown-service if no service name can be detected' do
      allow(Dir).to receive(:pwd).and_return('/')
      hide_const('Rails')
      ClimateControl.modify(EZLOGS_SERVICE_NAME: nil) do
        expect(described_class.new.service_name).to eq('unknown-service')
      end
    end

    it 'detects environment from ENV' do
      ClimateControl.modify(EZLOGS_ENVIRONMENT: 'env-test') do
        expect(described_class.new.environment).to eq('env-test')
      end
    end

    it 'falls back to development if no environment can be detected' do
      hide_const('Rails')
      ClimateControl.modify(EZLOGS_ENVIRONMENT: nil, RAILS_ENV: nil, RACK_ENV: nil) do
        expect(described_class.new.environment).to eq('development')
      end
    end

    it 'detects job adapter as :sidekiq if Sidekiq is defined' do
      stub_const('Sidekiq', Class.new)
      expect(described_class.new.job_adapter).to eq(:sidekiq)
    end

    it 'detects job adapter as :active_job if only ActiveJob is defined' do
      hide_const('Sidekiq')
      stub_const('ActiveJob', Class.new)
      expect(described_class.new.job_adapter).to eq(:active_job)
    end
  end

  describe 'deprecated and DSL methods' do
    it 'warns when using collect' do
      expect { config.collect }.to output(/deprecated/).to_stderr
    end
    it 'raises if collect is called when frozen' do
      config.freeze!
      expect { config.collect { |c| c.http = false } }.to raise_error(EzlogsRubyAgent::ConfigurationError)
    end
    it 'raises if instrumentation is called when frozen' do
      config.freeze!
      expect { config.instrumentation { |c| c.http = false } }.to raise_error(EzlogsRubyAgent::ConfigurationError)
    end
    it 'raises if security is called when frozen' do
      config.freeze!
      expect { config.security { |c| c.auto_detect_pii = false } }.to raise_error(EzlogsRubyAgent::ConfigurationError)
    end
    it 'raises if performance is called when frozen' do
      config.freeze!
      expect { config.performance { |c| c.sample_rate = 0.5 } }.to raise_error(EzlogsRubyAgent::ConfigurationError)
    end
    it 'raises if delivery is called when frozen' do
      config.freeze!
      expect { config.delivery { |c| c.timeout = 10 } }.to raise_error(EzlogsRubyAgent::ConfigurationError)
    end
    it 'raises if correlation is called when frozen' do
      config.freeze!
      expect do
        config.correlation do |c|
          c.enable_correlation = false
        end
      end.to raise_error(EzlogsRubyAgent::ConfigurationError)
    end
  end

  describe 'summary' do
    it 'returns a human-readable summary' do
      expect(config.summary).to include('EZLogs Configuration Summary')
      expect(config.summary).to include('Service:')
      expect(config.summary).to include('Environment:')
    end
  end

  describe 'load_from_environment!' do
    it 'loads settings from ENV' do
      ClimateControl.modify(EZLOGS_SERVICE_NAME: 'env-service', EZLOGS_ENVIRONMENT: 'env-test',
                            EZLOGS_SAMPLE_RATE: '0.5', EZLOGS_ENDPOINT: 'http://env', EZLOGS_TIMEOUT: '42') do
        config.load_from_environment!
        expect(config.service_name).to eq('env-service')
        expect(config.environment).to eq('env-test')
        expect(config.performance.sample_rate).to eq(0.5)
        expect(config.delivery.endpoint).to eq('http://env')
        expect(config.delivery.timeout).to eq(42)
      end
    end
  end
end
