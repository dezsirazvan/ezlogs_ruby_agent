require 'spec_helper'

RSpec.describe EzlogsRubyAgent::DeliveryEngine do
  let(:config) { EzlogsRubyAgent.config }
  let(:engine) { described_class.new(config) }

  before do
    config.delivery.endpoint = 'https://logs.example.com/events'
    config.delivery.timeout = 5
    config.delivery.retry_attempts = 2
    config.delivery.retry_backoff = 1.0
    config.delivery.circuit_breaker_threshold = 3
    config.delivery.circuit_breaker_timeout = 30
  end

  describe '#deliver' do
    let(:event_data) { { event_id: 'evt_123', event_type: 'test.event' } }

    it 'successfully delivers events' do
      stub_request(:post, 'https://logs.example.com/events')
        .with(body: event_data.to_json)
        .to_return(status: 200)

      result = engine.deliver(event_data)

      expect(result.success?).to be true
      expect(result.status_code).to eq(200)
    end

    it 'retries on temporary failures' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 500)
        .then.to_return(status: 200)

      result = engine.deliver(event_data)

      expect(result.success?).to be true
      expect(result.retry_count).to eq(1)
    end

    it 'fails after max retry attempts' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 500)

      result = engine.deliver(event_data)

      expect(result.success?).to be false
      expect(result.status_code).to eq(500)
      expect(result.retry_count).to eq(2)
    end

    it 'respects timeout configuration' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_timeout

      result = engine.deliver(event_data)

      expect(result.success?).to be false
      expect(result.error).to include('timeout')
    end

    it 'sends custom headers' do
      config.delivery.headers = { 'Authorization' => 'Bearer token123', 'X-Custom' => 'value' }

      stub_request(:post, 'https://logs.example.com/events')
        .with(headers: { 'Authorization' => 'Bearer token123', 'X-Custom' => 'value' })
        .to_return(status: 200)

      result = engine.deliver(event_data)

      expect(result.success?).to be true
    end

    it 'compresses large payloads when enabled' do
      config.performance.compression_enabled = true
      config.performance.compression_threshold = 100

      large_event = { event_id: 'evt_123', data: 'x' * 200 }

      stub_request(:post, 'https://logs.example.com/events')
        .with(headers: { 'Content-Encoding' => 'gzip' })
        .to_return(status: 200)

      result = engine.deliver(large_event)

      expect(result.success?).to be true
    end
  end

  describe 'circuit breaker' do
    let(:event_data) { { event_id: 'evt_123', event_type: 'test.event' } }

    it 'opens circuit breaker after threshold failures' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 500)

      # First 3 failures should trigger circuit breaker
      3.times do
        result = engine.deliver(event_data)
        expect(result.success?).to be false
      end

      # Next request should be rejected immediately
      result = engine.deliver(event_data)
      expect(result.success?).to be false
      expect(result.error).to include('circuit breaker open')
    end

    it 'closes circuit breaker after timeout' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 500)

      # Open circuit breaker
      3.times { engine.deliver(event_data) }

      # Wait for timeout and try again
      Timecop.travel(Time.now + 31) do
        stub_request(:post, 'https://logs.example.com/events')
          .to_return(status: 200)

        result = engine.deliver(event_data)
        expect(result.success?).to be true
      end
    end

    it 'resets circuit breaker on successful request' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 500)
        .then.to_return(status: 200)

      # First request: should retry and succeed
      result = engine.deliver(event_data)
      expect(result.success?).to be true

      # Circuit breaker should be closed
      expect(engine.circuit_breaker.closed?).to be true
    end
  end

  describe 'connection pooling' do
    it 'reuses connections for multiple requests' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 200)

      # Multiple requests should use the same connection
      result1 = engine.deliver({ event_id: 'evt_1' })
      result2 = engine.deliver({ event_id: 'evt_2' })
      result3 = engine.deliver({ event_id: 'evt_3' })

      expect(result1.success?).to be true
      expect(result2.success?).to be true
      expect(result3.success?).to be true
    end

    it 'handles connection pool exhaustion gracefully' do
      config.performance.max_concurrent_connections = 1

      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 200)

      # Should still work even with limited connections
      result = engine.deliver({ event_id: 'evt_123' })
      expect(result.success?).to be true
    end
  end

  describe 'batch delivery' do
    let(:events) do
      [
        { event_id: 'evt_1', event_type: 'test.event' },
        { event_id: 'evt_2', event_type: 'test.event' },
        { event_id: 'evt_3', event_type: 'test.event' }
      ]
    end

    it 'delivers batches efficiently' do
      stub_request(:post, 'https://logs.example.com/events')
        .with(body: /.*/)
        .to_return(status: 200)

      result = engine.deliver_batch(events)

      expect(result.success?).to be true
      expect(result.delivered_count).to eq(3)
    end

    it 'handles partial batch failures' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 207, body: {
          results: [
            { event_id: 'evt_1', status: 'success' },
            { event_id: 'evt_2', status: 'error', error: 'validation failed' },
            { event_id: 'evt_3', status: 'success' }
          ]
        }.to_json)

      result = engine.deliver_batch(events)

      expect(result.success?).to be false
      expect(result.delivered_count).to eq(2)
      expect(result.failed_count).to eq(1)
    end
  end

  describe 'health monitoring' do
    it 'provides health status' do
      health = engine.health_status

      expect(health).to include(
        circuit_breaker_state: be_a(String),
        connection_pool_size: be_a(Integer),
        total_requests: be_a(Integer),
        successful_requests: be_a(Integer),
        failed_requests: be_a(Integer)
      )
    end

    it 'tracks metrics over time' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 200)

      engine.deliver({ event_id: 'evt_123' })

      metrics = engine.metrics

      expect(metrics[:total_requests]).to eq(1)
      expect(metrics[:successful_requests]).to eq(1)
      expect(metrics[:failed_requests]).to eq(0)
      expect(metrics[:average_response_time]).to be_a(Float)
    end
  end

  describe 'graceful shutdown' do
    it 'completes pending requests on shutdown' do
      stub_request(:post, 'https://logs.example.com/events')
        .to_return(status: 200)

      # Start a request
      thread = Thread.new { engine.deliver({ event_id: 'evt_123' }) }

      # Shutdown while request is in progress
      engine.shutdown

      # Wait for completion
      thread.join

      expect(thread.value.success?).to be true
    end

    it 'closes all connections on shutdown' do
      engine.shutdown

      expect(engine.connection_pool.closed?).to be true
    end
  end

  describe 'local agent features' do
    before do
      config.delivery.endpoint = 'http://localhost:8080/events'
      config.delivery.agent_health_check = true
      config.delivery.agent_health_endpoint = '/health'
      config.service_name = 'test-app'
      config.environment = 'test'
    end

    it 'performs health check on local agent' do
      stub_request(:get, 'http://localhost:8080/health')
        .with(headers: { 'User-Agent' => /EzlogsRubyAgent/ })
        .to_return(status: 200, body: '{"status":"healthy"}')

      result = engine.agent_health_check

      expect(result[:healthy]).to be true
      expect(result[:status_code]).to eq(200)
    end

    it 'handles health check failures gracefully' do
      stub_request(:get, 'http://localhost:8080/health')
        .to_return(status: 503, body: '{"status":"unhealthy"}')

      result = engine.agent_health_check

      expect(result[:healthy]).to be false
      expect(result[:status_code]).to eq(503)
    end

    it 'includes local agent headers in requests' do
      stub_request(:post, 'http://localhost:8080/events')
        .with(
          headers: {
            'X-Ezlogs-Agent' => 'ruby',
            'X-Ezlogs-Version' => EzlogsRubyAgent::VERSION,
            'X-Ezlogs-Service' => 'test-app',
            'X-Ezlogs-Environment' => 'test'
          }
        )
        .to_return(status: 200)

      result = engine.deliver({ event_id: 'evt_123' })

      expect(result.success?).to be true
    end

    it 'skips health check when disabled' do
      config.delivery.agent_health_check = false

      result = engine.agent_health_check

      expect(result[:healthy]).to be true
      expect(result[:message]).to eq('Health check disabled')
    end
  end
end
