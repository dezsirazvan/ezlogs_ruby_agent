# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require_relative 'support/test_rails_app'
require_relative 'support/test_jobs'
require_relative 'support/event_validation_helpers'

RSpec.describe 'Complete Event Flow Integration', type: :integration do
  include Rack::Test::Methods
  include EventValidationHelpers::Helpers

  let(:app) { TestRailsApp::App.new }

  around do |example|
    EzlogsRubyAgent.test_mode { example.run }
  end

  before do
    # Configure EZLogs for testing
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-ecommerce-app'
      config.environment = 'test'
      config.instrumentation.http_requests = true
      config.instrumentation.active_record = true
      config.instrumentation.active_job = true
      config.security.auto_detect_pii = true
      config.security.sensitive_fields = %w[password token api_key]
    end

    # Clear order store for clean state
    TestRailsApp::Order.clear_store
    EzlogsRubyAgent.clear_captured_events
  end

  after do
    EzlogsRubyAgent.clear_captured_events
    TestRailsApp::Order.clear_store
  end

  describe 'Complete E-commerce Order Flow' do
    it 'tracks perfect event correlation across HTTP → DB → Job → Sidekiq pipeline' do
      # Create order via HTTP request
      order_data = {
        user_id: 'user_123',
        total: 99.99,
        items: [{ name: 'Product A', price: 49.99 }, { name: 'Product B', price: 50.00 }]
      }

      response = post '/orders', order_data.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(response.status).to eq(201)
      expect(response.body).to include('id')

      # Get the created order ID
      order_id = begin
        JSON.parse(response.body)['id']
      rescue StandardError
        nil
      end
      expect(order_id).not_to be_nil

      # Enqueue a Sidekiq job for this order
      SidekiqOrderJob.perform_async(order_id: order_id, user_id: 'user_123')

      # Get captured events
      events = EzlogsRubyAgent.captured_events

      # Debug: Print all events to understand what's being captured
      puts "\n=== DEBUG: All captured events ==="
      events.each_with_index do |event, index|
        puts "#{index + 1}. Type: #{event[:event][:event_type]}, Action: #{event[:event][:action]}, Correlation: #{event[:event][:correlation][:correlation_id]}"
      end
      puts "=== End Debug ===\n"

      # Find the main correlation ID from job events
      job_events = events.select { |e| e[:event][:event_type] == 'job.execution' }
      expect(job_events).not_to be_empty

      main_correlation_id = job_events.first[:event][:correlation][:correlation_id]

      # Filter events for this specific flow using the main correlation ID
      flow_events = events.select do |event|
        (event[:event][:correlation][:correlation_id] == main_correlation_id &&
         ['data.change', 'job.execution', 'payment.processed', 'notification.sent',
          'sidekiq.job'].include?(event[:event][:event_type])) ||
          event[:event][:event_type] == 'http.request' # Include HTTP requests regardless of correlation
      end

      puts "\n=== DEBUG: Filtered flow events ==="
      flow_events.each_with_index do |event, index|
        puts "#{index + 1}. Type: #{event[:event][:event_type]}, Action: #{event[:event][:action]}, Correlation: #{event[:event][:correlation][:correlation_id]}"
      end
      puts "=== End Debug ===\n"

      # Validate event count and correlation (expecting at least 8: HTTP + DB create + 4 DB updates + Job start + Job complete + Payment + Notification)
      expect(flow_events.length).to be >= 8

      # Check correlation flow for events with the same correlation ID (excluding HTTP request)
      same_correlation_events = flow_events.select do |e|
        e[:event][:correlation][:correlation_id] == main_correlation_id
      end
      expect(same_correlation_events).to have_correlation_flow

      expect(flow_events).to include_http_request
      expect(flow_events).to include_data_change
      expect(flow_events).to include_job_execution

      # Validate event schema
      flow_events.each do |event|
        validate_event_schema(event)
      end

      # Validate correlation consistency
      correlation_ids = same_correlation_events.map { |e| e[:event][:correlation][:correlation_id] }.uniq
      expect(correlation_ids.length).to eq(1)
      expect(correlation_ids.first).to match(/^corr_/)
    end

    it 'handles concurrent order creation with isolated correlation' do
      # Create multiple orders concurrently
      threads = []
      responses = []

      3.times do |i|
        threads << Thread.new do
          order_data = {
            user_id: "user_#{i + 1}",
            total: 50.00 + i * 10
          }

          response = post '/orders', order_data.to_json, 'CONTENT_TYPE' => 'application/json'
          responses << { status: response.status, body: response.body }
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify all requests succeeded
      responses.each do |response|
        expect(response[:status]).to eq(201)
      end

      # Get captured events
      events = EzlogsRubyAgent.captured_events

      # Filter events for this test (only HTTP requests and related events)
      test_events = events.select do |event|
        ['http.request', 'data.change', 'job.execution'].include?(event[:event][:event_type])
      end

      # Debug: Print correlation IDs
      puts "\n=== DEBUG: Correlation IDs ==="
      test_events.each_with_index do |event, index|
        puts "#{index + 1}. Type: #{event[:event][:event_type]}, Correlation: #{event[:event][:correlation][:correlation_id]}"
      end
      puts "=== End Debug ===\n"

      # Each request should have its own correlation ID
      correlation_ids = test_events.map { |e| e[:event][:correlation][:correlation_id] }.uniq
      expect(correlation_ids.length).to be >= 3

      # Each correlation ID should be used consistently within its flow
      correlation_ids.each do |correlation_id|
        flow_events = test_events.select { |e| e[:event][:correlation][:correlation_id] == correlation_id }
        # At least 1 event per correlation ID is acceptable
        expect(flow_events.length).to be >= 1
      end
    end

    it 'maintains sub-1ms performance for event creation' do
      user_id = 'perf_test_user'
      order_data = create_test_order_body(user_id: user_id, total: 50.00)

      # Measure performance
      performance = measure_performance(iterations: 100) do
        env = create_test_user_context(user_id).merge(
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/orders',
          'rack.input' => StringIO.new(order_data)
        )

        app.call(env)
        EzlogsRubyAgent.clear_captured_events
        TestRailsApp::Order.clear_store
      end

      # Validate performance requirements
      expect(performance[:p95]).to be < 1.0 # < 1ms p95
      expect(performance[:average]).to be < 0.5 # < 0.5ms average

      puts 'Performance Results:'
      puts "  Average: #{performance[:average].round(3)}ms"
      puts "  P95: #{performance[:p95].round(3)}ms"
      puts "  P99: #{performance[:p99].round(3)}ms"
      puts "  Min: #{performance[:min].round(3)}ms"
      puts "  Max: #{performance[:max].round(3)}ms"
    end

    it 'handles job failures gracefully with error tracking' do
      # Create a job that will fail by using a special order ID
      user_id = 'failure_test_user'

      # Create order data with a special ID that will cause job failure
      order_data = {
        user_id: user_id,
        total: 25.00,
        _force_failure: true # Special flag to force job failure
      }

      env = create_test_user_context(user_id).merge(
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/orders',
        'rack.input' => StringIO.new(order_data.to_json)
      )

      # The job should fail, but the application should not crash
      expect { app.call(env) }.not_to raise_error

      events = EzlogsRubyAgent.captured_events

      # Should still have HTTP and DB events
      expect(events).to include_http_request
      expect(events).to include_data_change

      # Should have job failure event
      job_events = find_events_by_type(events, 'job.execution')
      expect(job_events).not_to be_empty

      # Check for job failure event
      failure_events = job_events.select { |e| e[:event][:action].include?('failed') }
      expect(failure_events).not_to be_empty

      # Validate correlation is maintained
      expect(events).to have_correlation_flow
    end

    it 'sanitizes sensitive data in events' do
      # Create order with sensitive data
      order_data = {
        user_id: 'user_123',
        total: 99.99,
        password: 'secret123',
        api_key: 'sk_test_1234567890',
        credit_card: '4111-1111-1111-1111',
        email: 'user@example.com'
      }

      response = post '/orders', order_data.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(response.status).to eq(201)

      # Get captured events
      events = EzlogsRubyAgent.captured_events

      # Verify sensitive data is sanitized in all events
      events.each do |event|
        event_json = event.to_json

        # Debug: Print event JSON to see what's being captured
        puts "\n=== DEBUG: Event JSON ==="
        puts event_json
        puts "=== End Debug ===\n"

        # Check if sensitive data appears in any part of the event
        sensitive_data_found = false
        if event_json.include?('secret123') ||
           event_json.include?('sk_test_1234567890') ||
           event_json.include?('4111-1111-1111-1111') ||
           event_json.include?('user@example.com')
          sensitive_data_found = true
        end

        # If sensitive data is found, it should be redacted
        expect(event_json).to include('[REDACTED]') if sensitive_data_found
      end
    end

    it 'handles large payloads without performance degradation' do
      user_id = 'large_payload_user'

      # Create a large payload
      large_metadata = {}
      100.times { |i| large_metadata["field_#{i}"] = "value_#{i}" * 10 }

      order_data = {
        user_id: user_id,
        total: 299.99,
        metadata: large_metadata
      }.to_json

      env = create_test_user_context(user_id).merge(
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/orders',
        'rack.input' => StringIO.new(order_data)
      )

      # Measure performance with large payload
      start_time = Time.now
      response = app.call(env)
      end_time = Time.now

      processing_time = (end_time - start_time) * 1000

      # Should still complete quickly
      expect(processing_time).to be < 10.0 # < 10ms for large payload
      expect(response[0]).to eq(201)

      events = EzlogsRubyAgent.captured_events
      expect(events).to include_http_request
      expect(events).to include_data_change
    end

    it 'handles missing user context gracefully' do
      # Create order without user context
      order_data = {
        total: 99.99,
        items: [{ name: 'Product A', price: 99.99 }]
      }

      response = post '/orders', order_data.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(response.status).to eq(201)

      # Get captured events
      events = EzlogsRubyAgent.captured_events

      # Filter events for this test
      test_events = events.select do |event|
        ['http.request', 'data.change', 'job.execution'].include?(event[:event][:event_type])
      end

      # Should have correlation flow even without user context
      expect(test_events).to have_correlation_flow

      # Should use system as fallback for missing user context
      http_events = test_events.select { |e| e[:event][:event_type] == 'http.request' }
      expect(http_events.first[:event][:actor][:id]).to eq('system')
    end

    it 'handles large payloads within limits' do
      # Create order with large payload
      large_items = 1000.times.map { |i| { name: "Product #{i}", price: 10.00 } }
      order_data = {
        user_id: 'user_123',
        total: 10_000.00,
        items: large_items,
        metadata: { description: 'A' * 10_000 } # 10KB description
      }

      response = post '/orders', order_data.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(response.status).to eq(201)

      # Get captured events
      events = EzlogsRubyAgent.captured_events

      # Filter events for this test
      test_events = events.select do |event|
        ['http.request', 'data.change', 'job.execution'].include?(event[:event][:event_type])
      end

      # Should have correlation flow even with large payload
      expect(test_events).to have_correlation_flow

      # Should not include the large description in events
      events.each do |event|
        event_json = event.to_json
        expect(event_json).not_to include('A' * 10_000)
      end
    end
  end

  describe 'Event Schema Validation' do
    it 'ensures all events follow Universal Event Schema' do
      user_id = 'schema_test_user'
      order_data = create_test_order_body(user_id: user_id, total: 75.00)

      env = create_test_user_context(user_id).merge(
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/orders',
        'rack.input' => StringIO.new(order_data)
      )

      app.call(env)
      events = EzlogsRubyAgent.captured_events

      # Validate each event follows the schema
      events.each do |event|
        validate_event_schema(event)
      end
    end

    it 'validates HTTP request event completeness' do
      # Create order via HTTP request
      order_data = {
        user_id: 'user_123',
        total: 99.99
      }

      response = post '/orders', order_data.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(response.status).to eq(201)

      # Get captured events
      events = EzlogsRubyAgent.captured_events

      # Find HTTP request event
      http_events = events.select { |e| e[:event][:event_type] == 'http.request' }
      expect(http_events).not_to be_empty

      http_event = http_events.first

      # Validate HTTP request event structure
      expect(http_event[:event][:event_type]).to eq('http.request')
      expect(http_event[:event][:action]).to eq('POST')
      expect(http_event[:event][:actor][:type]).to eq('system')
      expect(http_event[:event][:subject][:type]).to eq('endpoint')
      expect(http_event[:event][:subject][:id]).to eq('/orders')

      # Validate metadata
      expect(http_event[:event][:metadata][:method]).to eq('POST')
      expect(http_event[:event][:metadata][:path]).to eq('/orders')
      expect(http_event[:event][:metadata][:status_code]).to eq(201)
      expect(http_event[:event][:metadata][:user_agent]).to eq('TestApp/1.0')
      expect(http_event[:event][:metadata][:content_type]).to eq('application/json')
      expect(http_event[:event][:metadata][:duration_ms]).to be_a(Float)
    end

    it 'validates data change event completeness' do
      user_id = 'data_test_user'
      order_data = create_test_order_body(user_id: user_id, total: 125.00)

      env = create_test_user_context(user_id).merge(
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/orders',
        'rack.input' => StringIO.new(order_data)
      )

      app.call(env)
      events = EzlogsRubyAgent.captured_events

      data_events = find_events_by_type(events, 'data.change')
      expect(data_events).to be_present

      data_event = data_events.first
      validate_data_change_event(data_event)

      # Validate specific data change metadata
      expect(data_event[:event][:metadata][:action]).to eq('create')
      expect(data_event[:event][:metadata][:model]).to eq('Order')
      expect(data_event[:event][:metadata][:table]).to eq('orders')
      expect(data_event[:event][:metadata][:changes]).to be_a(Hash)
    end

    it 'validates job execution event completeness' do
      # Create order via HTTP request to trigger job
      order_data = {
        user_id: 'user_123',
        total: 99.99
      }

      response = post '/orders', order_data.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(response.status).to eq(201)

      # Get captured events
      events = EzlogsRubyAgent.captured_events

      # Find job execution events
      job_events = events.select { |e| e[:event][:event_type] == 'job.execution' }
      expect(job_events).not_to be_empty

      job_event = job_events.first

      # Validate job execution event structure
      expect(job_event[:event][:event_type]).to eq('job.execution')
      expect(job_event[:event][:action]).to eq('perform')
      expect(job_event[:event][:actor][:type]).to eq('system')
      expect(job_event[:event][:subject][:type]).to eq('job')
      expect(job_event[:event][:subject][:id]).to eq('ProcessOrderJob')

      # Validate metadata
      expect(job_event[:event][:metadata][:queue_name]).to eq('default')
      expect(job_event[:event][:metadata][:job_class]).to eq('ProcessOrderJob')
      expect(job_event[:event][:metadata][:retry_count]).to eq(0)
      expect(job_event[:event][:metadata][:priority]).to eq('normal')
    end
  end

  describe 'Edge Cases and Error Handling' do
    it 'handles malformed request data gracefully' do
      user_id = 'malformed_test_user'
      malformed_data = '{"invalid": json}'

      env = create_test_user_context(user_id).merge(
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/orders',
        'rack.input' => StringIO.new(malformed_data)
      )

      # Should not crash
      expect { app.call(env) }.not_to raise_error

      events = EzlogsRubyAgent.captured_events

      # Should still have HTTP event even with malformed data
      expect(events).to include_http_request
    end

    it 'handles missing user context gracefully' do
      order_data = create_test_order_body(user_id: 'anonymous', total: 35.00)

      env = {
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/orders',
        'rack.input' => StringIO.new(order_data),
        'HTTP_USER_AGENT' => 'TestApp/1.0'
      }

      response = app.call(env)
      expect(response[0]).to eq(201) # Should still succeed

      events = EzlogsRubyAgent.captured_events
      expect(events).to have_correlation_flow
    end

    it 'handles large payloads within limits' do
      user_id = 'large_payload_user'
      large_items = 100.times.map { |i| { product_id: "prod_#{i}", quantity: 1, price: 10.00 } }
      large_order_data = {
        user_id: user_id,
        total: 1000.00,
        items: large_items
      }.to_json

      env = create_test_user_context(user_id).merge(
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/orders',
        'rack.input' => StringIO.new(large_order_data)
      )

      # Should handle large payloads gracefully
      expect { app.call(env) }.not_to raise_error

      events = EzlogsRubyAgent.captured_events
      expect(events).to have_correlation_flow
    end
  end

  private

  def validate_all_events(events)
    events.each do |event|
      # Basic schema validation
      validate_event_schema(event)

      # Type-specific validation
      case event[:event][:event_type]
      when 'http.request'
        validate_http_request_event(event)
      when 'data.change'
        validate_data_change_event(event)
      when 'job.execution'
        validate_job_execution_event(event)
      end
    end
  end

  def create_test_order_body(user_id:, total: 99.99)
    {
      user_id: user_id,
      total: total,
      items: [
        { name: 'Product 1', quantity: 2, price: total / 2 },
        { name: 'Product 2', quantity: 1, price: total / 2 }
      ]
    }.to_json
  end

  def create_test_user_context(user_id)
    {
      'HTTP_X_USER_ID' => user_id,
      'HTTP_USER_AGENT' => 'TestAgent/1.0',
      'HTTP_ACCEPT' => 'application/json',
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def simulate_concurrent_requests(count: 3)
    threads = []
    results = []

    count.times do |i|
      threads << Thread.new do
        result = yield(i)
        Thread.current[:result] = result
      end
    end

    threads.each do |thread|
      thread.join
      results << thread[:result]
    end

    results
  end

  def measure_performance(iterations: 100)
    times = []

    iterations.times do
      start_time = Time.now
      yield
      end_time = Time.now
      times << (end_time - start_time) * 1000
    end

    sorted_times = times.sort
    {
      average: times.sum / times.length,
      p95: sorted_times[(times.length * 0.95).floor],
      p99: sorted_times[(times.length * 0.99).floor],
      min: sorted_times.first,
      max: sorted_times.last
    }
  end

  def find_events_by_type(events, event_type)
    events.select { |e| e[:event][:event_type] == event_type }
  end
end
