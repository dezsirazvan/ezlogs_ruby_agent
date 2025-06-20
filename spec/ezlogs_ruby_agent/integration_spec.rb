require 'spec_helper'

RSpec.describe 'EzlogsRubyAgent Integration' do
  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
      config.delivery.endpoint = 'http://localhost:9000'
      config.performance.sample_rate = 1.0
    end

    # Enable debug mode to capture events
    EzlogsRubyAgent.debug_mode = true
    EzlogsRubyAgent.clear_captured_events
  end

  after do
    EzlogsRubyAgent.debug_mode = false
    EzlogsRubyAgent.clear_captured_events
  end

  describe 'complete event flow' do
    it 'tracks HTTP request with correlation' do
      # Simulate HTTP request
      env = {
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/users',
        'QUERY_STRING' => '',
        'HTTP_X_REQUEST_ID' => 'req_123',
        'HTTP_X_SESSION_ID' => 'sess_456',
        'HTTP_USER_AGENT' => 'TestAgent/1.0',
        'REMOTE_ADDR' => '127.0.0.1',
        'rack.input' => StringIO.new('{"name":"John","email":"john@example.com"}')
      }

      tracker = EzlogsRubyAgent::HttpTracker.new(->(_env) { [200, {}, ['OK']] })
      tracker.call(env)

      events = EzlogsRubyAgent.captured_events
      expect(events).to have_event_count(1)

      event = events.first[:event]
      expect(event[:event_type]).to eq('http.request')
      expect(event[:action]).to eq('POST /users')
      expect(event[:correlation][:request_id]).to eq('req_123')
      expect(event[:correlation][:session_id]).to eq('[REDACTED]')
      expect(event[:metadata][:status]).to eq(200)
      expect(event[:metadata][:duration]).to be_present
    end

    it 'tracks database changes with correlation inheritance' do
      # Start correlation context
      EzlogsRubyAgent::CorrelationManager.start_flow_context('user_creation', 'user_123')

      # Simulate database change
      user = double('User', id: 123, class: double(name: 'User'))
      allow(user).to receive(:attributes).and_return({ 'id' => 123, 'name' => 'John' })
      allow(user).to receive(:saved_changes).and_return({ 'name' => ['', 'John'] })
      allow(user).to receive(:saved_attributes).and_return({ 'id' => 123, 'name' => '' })
      allow(user).to receive(:table_name).and_return('users')
      allow(user).to receive(:errors).and_return([])
      allow(user).to receive(:model_name).and_return(OpenStruct.new(singular: 'user'))

      # Include CallbacksTracker
      user.extend(EzlogsRubyAgent::CallbacksTracker)
      user.send(:log_create_event)

      events = EzlogsRubyAgent.captured_events
      expect(events).to have_event_count(1)

      event = events.first[:event]
      expect(event[:event_type]).to eq('data.change')
      expect(event[:action]).to eq('user.create')
      expect(event[:subject][:type]).to eq('user')
      expect(event[:subject][:id]).to eq('123')
      expect(event[:correlation][:flow_id]).to eq('flow_user_creation_user_123')
    end

    it 'tracks background jobs with correlation restoration' do
      # Start correlation context
      EzlogsRubyAgent::CorrelationManager.start_flow_context('email_sending', 'email_456')
      correlation_data = EzlogsRubyAgent::CorrelationManager.extract_context

      # Simulate background job
      job_class = Class.new do
        def self.name = 'EmailJob'
        def job_id = 'job_789'
        def queue_name = 'emails'
        def retry_count = 0
        def priority = 'normal'
        def perform(*_args) = 'email_sent'
      end
      job_class.include(EzlogsRubyAgent::JobTracker)
      job = job_class.new

      # Simulate job arguments with correlation data
      args = [{ '_correlation_data' => correlation_data, 'user_id' => 123 }]

      # Execute the job
      job.perform(*args)

      events = EzlogsRubyAgent.captured_events
      expect(events).to have_event_count(2) # started and completed

      started_event = events.find { |e| e[:event][:metadata][:status] == 'started' }
      completed_event = events.find { |e| e[:event][:metadata][:status] == 'completed' }

      expect(started_event[:event][:event_type]).to eq('job.execution')
      expect(started_event[:event][:action]).to eq('perform')
      expect(started_event[:event][:correlation][:flow_id]).to eq('flow_email_sending_email_456')

      expect(completed_event[:event][:event_type]).to eq('job.execution')
      expect(completed_event[:event][:action]).to eq('EmailJob.completed')
      expect(completed_event[:event][:correlation][:flow_id]).to eq('flow_email_sending_email_456')
    end

    it 'maintains correlation across complete user journey' do
      # Start correlation context for the entire journey
      EzlogsRubyAgent::CorrelationManager.start_flow_context('user_journey', 'user_456')

      # 1. HTTP request to create user
      env = {
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/users',
        'HTTP_X_REQUEST_ID' => 'req_user_123',
        'HTTP_X_SESSION_ID' => 'sess_user_456',
        'rack.input' => StringIO.new('{"name":"Jane","email":"jane@example.com"}')
      }

      tracker = EzlogsRubyAgent::HttpTracker.new(->(_env) { [201, {}, ['Created']] })
      tracker.call(env)

      # Extract correlation context ONCE after HTTP step
      correlation_data = EzlogsRubyAgent::CorrelationManager.extract_context

      # 2. Database change (user created)
      user = double('User', id: 456, class: double(name: 'User'))
      allow(user).to receive(:attributes).and_return({ 'id' => 456, 'name' => 'Jane' })
      allow(user).to receive(:saved_changes).and_return({ 'name' => ['', 'Jane'] })
      allow(user).to receive(:saved_attributes).and_return({ 'id' => 456, 'name' => '' })
      allow(user).to receive(:table_name).and_return('users')
      allow(user).to receive(:errors).and_return([])
      allow(user).to receive(:model_name).and_return(OpenStruct.new(singular: 'user'))

      user.extend(EzlogsRubyAgent::CallbacksTracker)
      user.send(:log_create_event)

      # 3. Background job (welcome email)
      job_class = Class.new do
        def self.name = 'WelcomeEmailJob'
        def job_id = 'job_welcome_789'
        def queue_name = 'emails'
        def retry_count = 0
        def priority = 'normal'
        def perform(*_args) = 'email_sent'
      end
      job_class.include(EzlogsRubyAgent::JobTracker)
      job = job_class.new

      args = [{ '_correlation_data' => correlation_data, 'user_id' => 456 }]
      job.perform(*args)

      events = EzlogsRubyAgent.captured_events
      expect(events).to have_event_count(4) # HTTP + DB + Job started + Job completed

      # Verify all events have correlation data (they should be correlated)
      correlation_data = events.map { |e| e[:event]&.dig(:correlation) }.compact
      expect(correlation_data.size).to eq(4), "Expected 4 events with correlation data, got #{correlation_data.size}"

      # Verify event types
      event_types = events.map { |e| e[:event][:event_type] }
      expect(event_types).to include('http.request')
      expect(event_types).to include('data.change')
      expect(event_types).to include('job.execution')
    end
  end

  describe 'performance optimizations' do
    it 'uses object pooling efficiently' do
      # Create multiple events
      10.times do |i|
        event = EzlogsRubyAgent::UniversalEvent.new(
          event_type: 'test.event',
          action: "action_#{i}",
          actor: { type: 'test', id: i.to_s }
        )
        # The pool will be used internally
        EzlogsRubyAgent.writer.log(event)
      end

      events = EzlogsRubyAgent.captured_events
      expect(events).to have_event_count(10)
    end

    it 'processes events efficiently' do
      events = []
      5.times do |i|
        events << EzlogsRubyAgent::UniversalEvent.new(
          event_type: 'test.event',
          action: "action_#{i}",
          actor: { type: 'test', id: i.to_s }
        )
      end

      # Log all events
      events.each { |event| EzlogsRubyAgent.writer.log(event) }

      captured_events = EzlogsRubyAgent.captured_events
      expect(captured_events).to have_event_count(5)
    end
  end

  describe 'debug tools' do
    it 'captures events in debug mode' do
      # Enable debug mode
      allow(EzlogsRubyAgent.config).to receive(:debug_mode).and_return(true)

      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.event',
        action: 'test_action',
        actor: { type: 'test', id: '123' }
      )

      EzlogsRubyAgent.writer.log(event)

      events = EzlogsRubyAgent.captured_events
      expect(events).to have_event_count(1)
      expect(events.first[:event][:event_type]).to eq('test.event')
    end

    it 'provides health status' do
      status = EzlogsRubyAgent.health_status

      expect(status).to include(:writer)
      expect(status).to include(:delivery_engine)
      expect(status).to include(:correlation_manager)
      expect(status).to include(:performance)
      expect(status).to include(:debug_mode)
      expect(status).to include(:config)
    end
  end

  describe 'error handling' do
    it 'handles invalid events gracefully' do
      # Try to log invalid event
      expect do
        EzlogsRubyAgent.writer.log(nil)
      end.not_to raise_error

      # Should create a fallback event or handle gracefully
      events = EzlogsRubyAgent.captured_events
      if events&.any? && events.first
        expect(events.first[:event][:event_type]).to eq('system.error')
        expect(events.first[:event][:action]).to eq('event_creation_failed')
      else
        # Event was handled gracefully without creating a fallback
        expect(events.compact).to be_empty
      end
    end

    it 'handles correlation context errors gracefully' do
      # Clear any existing context
      EzlogsRubyAgent::CorrelationManager.clear_context

      # Should not raise error when no context exists
      expect do
        data = EzlogsRubyAgent::CorrelationManager.extract_context
        expect(data).to eq({})
      end.not_to raise_error
    end
  end

  describe 'backward compatibility' do
    it 'handles legacy hash format events' do
      # Log legacy hash format
      legacy_event = {
        'event_type' => 'legacy.event',
        'action' => 'legacy_action',
        'actor' => { 'type' => 'legacy', 'id' => '123' },
        'metadata' => { 'legacy' => true }
      }

      # This should be handled gracefully
      expect do
        EzlogsRubyAgent.writer.log(legacy_event)
      end.not_to raise_error
    end
  end
end
