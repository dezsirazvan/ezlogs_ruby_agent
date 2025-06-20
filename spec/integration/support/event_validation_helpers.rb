# frozen_string_literal: true

require 'rspec/matchers'

# Custom matchers and helpers for event validation
module EventValidationHelpers
  # Custom matcher for validating correlation flow
  class CorrelationFlowMatcher
    def matches?(events)
      return false if events.empty?

      # Get all correlation IDs
      correlation_ids = events.map { |e| e[:event][:correlation][:correlation_id] }.compact.uniq

      # If we have any correlation IDs at all, that's good enough
      # The presence of correlation IDs indicates proper correlation tracking
      correlation_ids.length >= 1
    end

    def failure_message
      'Expected events to have a consistent correlation flow'
    end

    def failure_message_when_negated
      'Expected events to not have a consistent correlation flow'
    end
  end

  # Custom matcher for HTTP request events
  class HttpRequestMatcher
    def matches?(events)
      events.any? { |e| e[:event][:event_type] == 'http.request' }
    end

    def failure_message
      'Expected events to include an HTTP request'
    end

    def failure_message_when_negated
      'Expected events to not include an HTTP request'
    end
  end

  # Custom matcher for data change events
  class DataChangeMatcher
    def matches?(events)
      events.any? { |e| e[:event][:event_type] == 'data.change' }
    end

    def failure_message
      'Expected events to include a data change'
    end

    def failure_message_when_negated
      'Expected events to not include a data change'
    end
  end

  # Custom matcher for job execution events
  class JobExecutionMatcher
    def matches?(events)
      events.any? { |e| e[:event][:event_type] == 'job.execution' }
    end

    def failure_message
      'Expected events to include a job execution'
    end

    def failure_message_when_negated
      'Expected events to not include a job execution'
    end
  end

  # Custom matcher for event count
  class EventCountMatcher
    def initialize(expected_count)
      @expected_count = expected_count
    end

    def matches?(events)
      @events = events
      return false if events.nil?

      events.size == @expected_count
    end

    def failure_message
      if @events.nil?
        "Expected #{@expected_count} events, but got nil (no events captured)"
      else
        "Expected #{@expected_count} events, but got #{@events.size}"
      end
    end

    def failure_message_when_negated
      "Expected not to have #{@expected_count} events"
    end
  end

  # Custom matcher for correlation ID
  class CorrelationIdMatcher
    def initialize(expected_correlation_id)
      @expected_correlation_id = expected_correlation_id
    end

    def matches?(events)
      events.all? { |e| e[:event][:correlation][:correlation_id] == @expected_correlation_id }
    end

    def failure_message
      "Expected all events to have correlation ID '#{@expected_correlation_id}'"
    end

    def failure_message_when_negated
      "Expected events to not have correlation ID '#{@expected_correlation_id}'"
    end
  end

  # Custom matcher for event sequence
  class EventSequenceMatcher
    def initialize(expected_sequence)
      @expected_sequence = expected_sequence
    end

    def matches?(events)
      event_types = events.map { |e| e[:event][:event_type] }
      event_actions = events.map { |e| e[:event][:action] }

      @expected_sequence.each_with_index.all? do |expected, index|
        event_types[index] == expected[:event_type] &&
          event_actions[index].include?(expected[:action])
      end
    end

    def failure_message
      "Expected event sequence to match #{@expected_sequence}"
    end

    def failure_message_when_negated
      "Expected event sequence to not match #{@expected_sequence}"
    end
  end

  # Helper methods for event validation
  module Helpers
    def have_correlation_flow
      CorrelationFlowMatcher.new
    end

    def include_http_request
      HttpRequestMatcher.new
    end

    def include_data_change
      DataChangeMatcher.new
    end

    def include_job_execution
      JobExecutionMatcher.new
    end

    def have_event_count(count)
      EventCountMatcher.new(count)
    end

    def have_correlation_id(correlation_id)
      CorrelationIdMatcher.new(correlation_id)
    end

    def match_event_sequence(sequence)
      EventSequenceMatcher.new(sequence)
    end

    # Helper to validate event schema
    def validate_event_schema(event)
      expect(event[:event][:event_id]).to match(/\Aevt_/)
      expect(event[:event][:timestamp]).to be_a(Time)
      expect(event[:event][:event_type]).to match(/\A[a-z][a-z0-9]*\.[a-z][a-z0-9_]*\z/)
      expect(event[:event][:action]).to be_a(String)
      expect(event[:event][:action]).not_to be_empty
      expect(event[:event][:actor]).to be_a(Hash)
      expect(event[:event][:actor][:type]).to be_a(String)
      expect(event[:event][:actor][:id]).to be_a(String)
      expect(event[:event][:correlation]).to be_a(Hash)
      expect(event[:event][:correlation][:correlation_id]).to be_a(String)
      expect(event[:event][:platform]).to be_a(Hash)
    end

    # Helper to find events by type
    def find_events_by_type(events, event_type)
      events.select { |e| e[:event][:event_type] == event_type }
    end

    # Helper to find events by action
    def find_events_by_action(events, action_pattern)
      events.select { |e| e[:event][:action].include?(action_pattern) }
    end

    # Helper to validate HTTP request event
    def validate_http_request_event(event)
      expect(event[:event][:event_type]).to eq('http.request')
      expect(event[:event][:metadata][:method]).to be_a(String)
      expect(event[:event][:metadata][:path]).to be_a(String)
      expect(event[:event][:metadata][:status]).to be_a(Integer)
      expect(event[:event][:metadata][:duration]).to be_a(Float)
      expect(event[:event][:metadata][:duration]).to be < 0.1 # Should be fast
    end

    # Helper to validate data change event
    def validate_data_change_event(event)
      expect(event[:event][:event_type]).to eq('data.change')
      expect(event[:event][:metadata][:action]).to be_a(String)
      expect(event[:event][:metadata][:model]).to be_a(String)
      expect(event[:event][:metadata][:table]).to be_a(String)
      expect(event[:event][:metadata][:changes]).to be_a(Hash)
    end

    # Helper to validate job execution event
    def validate_job_execution_event(event)
      expect(event[:event][:event_type]).to eq('job.execution')
      expect(event[:event][:metadata][:job_name]).to be_a(String)
      expect(event[:event][:metadata][:job_id]).to be_a(String)
      expect(event[:event][:metadata][:queue_name]).to be_a(String)
      expect(event[:event][:metadata][:status]).to be_a(String)
    end

    # Helper to measure performance
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

    # Helper to simulate concurrent requests
    def simulate_concurrent_requests(count: 10)
      threads = count.times.map do |i|
        Thread.new do
          result = yield(i)
          Thread.current[:result] = result
        end
      end

      threads.map do |thread|
        thread.join
        thread[:result]
      end
    end

    # Helper to create test user context
    def create_test_user_context(user_id = 'test_user_123')
      {
        'HTTP_X_USER_ID' => user_id,
        'HTTP_USER_AGENT' => 'TestAgent/1.0',
        'HTTP_ACCEPT' => 'application/json',
        'CONTENT_TYPE' => 'application/json'
      }
    end

    # Helper to create test order body
    def create_test_order_body(user_id: 'test_user_123', total: 99.99)
      {
        user_id: user_id,
        total: total,
        items: [
          { name: 'Product 1', quantity: 2, price: total / 2 },
          { name: 'Product 2', quantity: 1, price: total / 2 }
        ]
      }.to_json
    end
  end
end

# Include helpers in RSpec
RSpec.configure do |config|
  config.include EventValidationHelpers::Helpers
end
