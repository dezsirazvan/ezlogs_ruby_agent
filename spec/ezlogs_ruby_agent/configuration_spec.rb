require 'spec_helper'

RSpec.describe EzlogsRubyAgent::Configuration do
  let(:config) { described_class.new }

  describe 'legacy configuration compatibility' do
    it 'maintains backward compatibility with existing attributes' do
      config.capture_http = false
      config.capture_callbacks = false
      config.capture_jobs = true
      config.resources_to_track = %w[User Order]
      config.exclude_resources = ['Admin']
      config.agent_host = '192.168.1.100'
      config.agent_port = 9090
      config.flush_interval = 5.0
      config.max_buffer_size = 10_000
      config.service_name = 'my-awesome-app'
      config.environment = 'staging'

      expect(config.capture_http).to be false
      expect(config.capture_callbacks).to be false
      expect(config.capture_jobs).to be true
      expect(config.resources_to_track).to eq(%w[User Order])
      expect(config.exclude_resources).to eq(['Admin'])
      expect(config.agent_host).to eq('192.168.1.100')
      expect(config.agent_port).to eq(9090)
      expect(config.flush_interval).to eq(5.0)
      expect(config.max_buffer_size).to eq(10_000)
      expect(config.service_name).to eq('my-awesome-app')
      expect(config.environment).to eq('staging')
    end
  end

  describe 'enhanced configuration DSL' do
    it 'supports nested collect configuration' do
      config.collect do |c|
        c.http_requests = true
        c.database_changes = false
        c.background_jobs = true
        c.custom_events = true
      end

      expect(config.collect.http_requests).to be true
      expect(config.collect.database_changes).to be false
      expect(config.collect.background_jobs).to be true
      expect(config.collect.custom_events).to be true
    end

    it 'supports nested security configuration' do
      config.security do |s|
        s.auto_detect_pii = true
        s.sanitize_fields = %w[password token api_key]
        s.max_payload_size = 32 * 1024
        s.custom_patterns = {
          'internal_id' => /^INT_\d{8}$/,
          'session_token' => /^sess_[a-zA-Z0-9]{32}$/
        }
      end

      expect(config.security.auto_detect_pii).to be true
      expect(config.security.sanitize_fields).to eq(%w[password token api_key])
      expect(config.security.max_payload_size).to eq(32 * 1024)
      expect(config.security.custom_patterns).to include('internal_id')
    end

    it 'supports nested performance configuration' do
      config.performance do |p|
        p.sample_rate = 0.1
        p.buffer_size = 5_000
        p.batch_size = 500
        p.flush_interval = 30
        p.max_concurrent_connections = 10
        p.compression_enabled = true
        p.compression_threshold = 1024
      end

      expect(config.performance.sample_rate).to eq(0.1)
      expect(config.performance.buffer_size).to eq(5_000)
      expect(config.performance.batch_size).to eq(500)
      expect(config.performance.flush_interval).to eq(30)
      expect(config.performance.max_concurrent_connections).to eq(10)
      expect(config.performance.compression_enabled).to be true
      expect(config.performance.compression_threshold).to eq(1024)
    end

    it 'supports nested delivery configuration' do
      config.delivery do |d|
        d.endpoint = 'https://logs.example.com/events'
        d.timeout = 10
        d.retry_attempts = 3
        d.retry_backoff = 2.0
        d.circuit_breaker_threshold = 5
        d.circuit_breaker_timeout = 60
        d.headers = { 'Authorization' => 'Bearer token123' }
      end

      expect(config.delivery.endpoint).to eq('https://logs.example.com/events')
      expect(config.delivery.timeout).to eq(10)
      expect(config.delivery.retry_attempts).to eq(3)
      expect(config.delivery.retry_backoff).to eq(2.0)
      expect(config.delivery.circuit_breaker_threshold).to eq(5)
      expect(config.delivery.circuit_breaker_timeout).to eq(60)
      expect(config.delivery.headers).to eq({ 'Authorization' => 'Bearer token123' })
    end

    it 'supports nested correlation configuration' do
      config.correlation do |c|
        c.enable_flow_tracking = true
        c.session_tracking = true
        c.user_tracking = true
        c.business_process_tracking = true
        c.max_flow_depth = 10
        c.flow_timeout = 3600
      end

      expect(config.correlation.enable_flow_tracking).to be true
      expect(config.correlation.session_tracking).to be true
      expect(config.correlation.user_tracking).to be true
      expect(config.correlation.business_process_tracking).to be true
      expect(config.correlation.max_flow_depth).to eq(10)
      expect(config.correlation.flow_timeout).to eq(3600)
    end
  end

  describe 'configuration validation' do
    it 'validates sample rate range' do
      expect do
        config.performance.sample_rate = 1.5
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError, /sample_rate must be between 0.0 and 1.0/)

      expect do
        config.performance.sample_rate = -0.1
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError, /sample_rate must be between 0.0 and 1.0/)
    end

    it 'validates buffer size limits' do
      expect do
        config.performance.buffer_size = 0
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError, /buffer_size must be positive/)

      expect do
        config.performance.buffer_size = 1_000_000
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError, /buffer_size cannot exceed 100,000/)
    end

    it 'validates endpoint format' do
      config.service_name = 'test-app'
      config.environment = 'development'

      expect do
        config.delivery.endpoint = 'http://example.com:invalid-port'
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError, /endpoint must be a valid URL/)

      expect do
        config.delivery.endpoint = 'ftp://example.com'
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError, /endpoint must use HTTP or HTTPS/)
    end

    it 'validates timeout values' do
      expect do
        config.delivery.timeout = -1
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError, /timeout must be positive/)

      expect do
        config.delivery.timeout = 300
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError, /timeout cannot exceed 60 seconds/)
    end
  end

  describe 'configuration loading' do
    it 'loads from Rails configuration file' do
      # This would test loading from config/ezlogs_ruby_agent.yml
      # Implementation will be added in the actual class
    end

    it 'loads from environment variables' do
      ENV['EZLOGS_SERVICE_NAME'] = 'env-service'
      ENV['EZLOGS_ENVIRONMENT'] = 'env-env'
      ENV['EZLOGS_SAMPLE_RATE'] = '0.5'

      config.load_from_environment!

      expect(config.service_name).to eq('env-service')
      expect(config.environment).to eq('env-env')
      expect(config.performance.sample_rate).to eq(0.5)
    ensure
      ENV.delete('EZLOGS_SERVICE_NAME')
      ENV.delete('EZLOGS_ENVIRONMENT')
      ENV.delete('EZLOGS_SAMPLE_RATE')
    end
  end

  describe 'configuration freezing' do
    it 'freezes configuration after initialization' do
      config.freeze!

      expect do
        config.service_name = 'new-name'
      end.to raise_error(FrozenError)

      expect do
        config.collect.http_requests = false
      end.to raise_error(FrozenError)
    end

    it 'allows modification before freezing' do
      config.service_name = 'test-app'
      config.collect.http_requests = false

      config.freeze!

      expect(config.service_name).to eq('test-app')
      expect(config.collect.http_requests).to be false
    end
  end

  describe 'configuration inspection' do
    it 'provides human-readable configuration summary' do
      config.service_name = 'my-app'
      config.environment = 'production'
      config.collect.http_requests = true
      config.performance.sample_rate = 0.1

      summary = config.summary

      expect(summary).to include('Service: my-app')
      expect(summary).to include('Environment: production')
      expect(summary).to include('HTTP Requests: enabled')
      expect(summary).to include('Sample Rate: 10%')
    end

    it 'validates complete configuration' do
      config.service_name = 'test-app'
      config.environment = 'development'
      config.delivery.endpoint = 'https://logs.example.com'

      validation = config.validate!

      expect(validation.valid?).to be true
      expect(validation.errors).to be_empty
    end

    it 'reports configuration errors' do
      config.performance.sample_rate = 1.5
      config.delivery.endpoint = 'invalid-url'

      expect do
        config.validate!
      end.to raise_error(EzlogsRubyAgent::ConfigurationError) do |error|
        expect(error.message).to include('sample_rate must be between')
        expect(error.message).to include('endpoint must use HTTP or HTTPS')
      end
    end
  end
end
