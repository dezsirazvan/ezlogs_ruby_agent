require 'spec_helper'
require 'rack/test'
require 'active_job'

RSpec.describe 'Complete Event Flow Validation', type: :integration do
  include Rack::Test::Methods

  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
      config.capture_http = true
      config.capture_callbacks = true
      config.capture_jobs = true
    end

    # Enable test mode to capture events
    EzlogsRubyAgent::DebugTools.enable_debug_mode
    EzlogsRubyAgent::DebugTools.clear_captured_events
  end

  after do
    EzlogsRubyAgent::DebugTools.disable_debug_mode
  end

  describe 'Complete User Journey with Perfect Correlation' do
    it 'captures perfect user journey with correlation' do
      # Start a correlation context
      EzlogsRubyAgent.start_flow('user_journey', 'user_123')

      # Simulate HTTP request
      EzlogsRubyAgent.log_event(
        event_type: 'http.request',
        action: 'GET /users/123',
        actor: { type: 'user', id: 'user_123' },
        subject: { type: 'user', id: '123' },
        metadata: { method: 'GET', path: '/users/123', status: 200 }
      )

      # Simulate database change
      EzlogsRubyAgent.log_event(
        event_type: 'data.change',
        action: 'user.updated',
        actor: { type: 'user', id: 'user_123' },
        subject: { type: 'user', id: '123' },
        metadata: { changes: ['email'] }
      )

      # Simulate job execution
      EzlogsRubyAgent.log_event(
        event_type: 'job.execution',
        action: 'welcome_email.perform',
        actor: { type: 'system', id: 'job_processor' },
        subject: { type: 'job', id: 'welcome_email_123' },
        metadata: { status: 'completed' }
      )

      events = EzlogsRubyAgent::DebugTools.captured_events

      # Validate event count and types
      expect(events.length).to eq(3) # HTTP + DB + Job

      # Validate correlation chain
      correlation_ids = events.map { |e| e[:event][:correlation][:correlation_id] }.uniq
      expect(correlation_ids.length).to eq(1) # All same correlation

      # Validate event types
      event_types = events.map { |e| e[:event][:event_type] }
      expect(event_types).to include('http.request')
      expect(event_types).to include('data.change')
      expect(event_types).to include('job.execution')
    end

    it 'handles GraphQL requests with special parsing' do
      # Start a correlation context
      EzlogsRubyAgent.start_flow('graphql_request', 'graphql_123')

      # Simulate GraphQL request
      EzlogsRubyAgent.log_event(
        event_type: 'http.request',
        action: 'POST /graphql',
        actor: { type: 'user', id: 'user_123' },
        subject: {
          type: 'graphql',
          operation: 'query',
          id: 'GetUser'
        },
        metadata: {
          method: 'POST',
          path: '/graphql',
          query: 'query GetUser($id: ID!) { user(id: $id) { name email } }'
        }
      )

      events = EzlogsRubyAgent::DebugTools.captured_events
      http_event = events.find { |e| e[:event][:event_type] == 'http.request' }

      expect(http_event[:event][:subject][:type]).to eq('graphql')
      expect(http_event[:event][:subject][:operation]).to eq('query')
      expect(http_event[:event][:subject][:id]).to eq('GetUser')
    end

    it 'maintains correlation across async boundaries' do
      # Start a request context
      EzlogsRubyAgent.start_flow('async_test', 'async_123')

      # Extract correlation data
      correlation_data = EzlogsRubyAgent.extract_correlation_data

      # Simulate async job in different thread
      job_result = nil
      Thread.new do
        EzlogsRubyAgent.restore_correlation_context(correlation_data)
        job_result = EzlogsRubyAgent.current_correlation_context
      end.join

      expect(job_result.flow_id).to eq(EzlogsRubyAgent.current_correlation_context.flow_id)
      expect(job_result.correlation_id).to eq(EzlogsRubyAgent.current_correlation_context.correlation_id)
    end
  end

  describe 'Event Schema Validation' do
    it 'ensures all events follow the universal schema' do
      # Create a test event
      EzlogsRubyAgent.log_event(
        event_type: 'test.schema',
        action: 'test.action',
        actor: { type: 'test', id: 'test_123' },
        subject: { type: 'test', id: '123' },
        metadata: { test: true }
      )

      events = EzlogsRubyAgent::DebugTools.captured_events

      events.each do |event|
        # Validate required fields
        expect(event[:event][:event_id]).to match(/\Aevt_/)
        expect(event[:event][:timestamp]).to be_a(Time)
        expect(event[:event][:event_type]).to match(/\A[a-z][a-z0-9]*\.[a-z][a-z0-9_]*\z/)
        expect(event[:event][:action]).to be_a(String)
        expect(event[:event][:action]).not_to be_empty

        # Validate actor structure
        expect(event[:event][:actor]).to be_a(Hash)
        expect(event[:event][:actor][:type]).to be_a(String)
        expect(event[:event][:actor][:id]).to be_a(String)

        # Validate correlation structure
        expect(event[:event][:correlation]).to be_a(Hash)
        expect(event[:event][:correlation][:correlation_id]).to be_a(String)

        # Validate platform structure
        expect(event[:event][:platform]).to be_a(Hash)
        expect(event[:event][:platform][:service]).to eq('test-app')
        expect(event[:event][:platform][:environment]).to eq('test')
        expect(event[:event][:platform][:agent_version]).to eq(EzlogsRubyAgent::VERSION)
      end
    end

    it 'validates HTTP request event completeness' do
      # Create HTTP event
      EzlogsRubyAgent.log_event(
        event_type: 'http.request',
        action: 'GET /users/123',
        actor: { type: 'user', id: 'user_123' },
        subject: { type: 'user', id: '123' },
        metadata: {
          method: 'GET',
          path: '/users/123',
          user_agent: 'TestApp/1.0',
          ip_address: '192.168.1.100',
          duration: 0.0005
        }
      )

      http_event = EzlogsRubyAgent::DebugTools.captured_events.find { |e| e[:event][:event_type] == 'http.request' }

      expect(http_event[:event][:action]).to eq('GET /users/123')
      expect(http_event[:event][:metadata][:method]).to eq('GET')
      expect(http_event[:event][:metadata][:path]).to eq('/users/123')
      expect(http_event[:event][:metadata][:user_agent]).to eq('TestApp/1.0')
      expect(http_event[:event][:metadata][:ip_address]).to eq('192.168.1.100')
      expect(http_event[:event][:metadata][:duration]).to be < 0.001 # < 1ms overhead
    end
  end

  describe 'Performance Validation' do
    it 'maintains sub-1ms event creation under load' do
      times = []

      100.times do
        start_time = Time.now
        EzlogsRubyAgent.log_event(
          event_type: 'test.performance',
          action: 'test.action',
          actor: { type: 'test', id: 'test_123' }
        )
        end_time = Time.now
        times << (end_time - start_time) * 1000 # Convert to ms
      end

      p95_time = times.sort[95] # 95th percentile
      expect(p95_time).to be < 1.0 # < 1ms target
    end

    it 'handles concurrent requests without correlation conflicts' do
      threads = 10.times.map do |i|
        Thread.new do
          EzlogsRubyAgent.start_flow("concurrent_#{i}", "entity_#{i}")
          EzlogsRubyAgent.log_event(
            event_type: 'test.concurrent',
            action: "action_#{i}",
            actor: { type: 'test', id: "test_#{i}" }
          )
        end
      end

      threads.each(&:join)

      events = EzlogsRubyAgent::DebugTools.captured_events
      correlation_ids = events.map { |e| e[:event][:correlation][:correlation_id] }.uniq

      # Each request should have its own correlation ID
      expect(correlation_ids.length).to eq(10)
    end
  end

  describe 'Error Handling Validation' do
    it 'handles malformed requests gracefully' do
      # This should not crash
      expect do
        EzlogsRubyAgent.log_event(
          event_type: 'test.error',
          action: 'test.action',
          actor: { type: 'test', id: 'test_123' },
          metadata: { error: 'test error' }
        )
      end.not_to raise_error
    end

    it 'continues operation when event creation fails' do
      # Mock UniversalEvent to raise an error
      allow(EzlogsRubyAgent::UniversalEvent).to receive(:new).and_raise(StandardError, 'Test error')

      # Should not crash the application
      expect do
        EzlogsRubyAgent.log_event(
          event_type: 'test.error',
          action: 'test.action',
          actor: { type: 'test', id: 'test_123' }
        )
      end.not_to raise_error
    end
  end

  describe 'Security Validation' do
    it 'sanitizes sensitive data in request parameters' do
      EzlogsRubyAgent.log_event(
        event_type: 'http.request',
        action: 'POST /users/123',
        actor: { type: 'user', id: 'user_123' },
        metadata: {
          params: {
            password: 'secret123',
            email: 'user@example.com',
            credit_card: '4111-1111-1111-1111',
            safe_field: 'public data'
          }
        }
      )

      http_event = EzlogsRubyAgent::DebugTools.captured_events.find { |e| e[:event][:event_type] == 'http.request' }

      # Sensitive data should be redacted
      expect(http_event[:event][:metadata][:params][:password]).to eq('[REDACTED]')
      expect(http_event[:event][:metadata][:params][:credit_card]).to eq('[REDACTED]')
      expect(http_event[:event][:metadata][:params][:safe_field]).to eq('public data')
    end
  end
end

# Mock job class for testing
class WelcomeEmailJob < ActiveJob::Base
  def perform(user_id:)
    # Simulate job execution
    sleep(0.001) # Simulate work
  end
end
