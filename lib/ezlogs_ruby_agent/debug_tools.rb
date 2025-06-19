require 'json'
require 'time'

module EzlogsRubyAgent
  # DebugTools provides comprehensive debugging and testing capabilities
  # for the EzlogsRubyAgent system, including event capture, correlation
  # tracking, and performance monitoring.
  #
  # @example Enable debug mode
  #   EzlogsRubyAgent.debug_mode = true
  #
  # @example Capture events in test
  #   EzlogsRubyAgent.test_mode do
  #     # Perform actions that generate events
  #     events = EzlogsRubyAgent.captured_events
  #     expect(events).to have_correlation_flow
  #   end
  module DebugTools
    # Debug mode configuration
    class << self
      attr_accessor :debug_mode, :capture_events, :log_level

      # Initialize debug tools
      def initialize
        @debug_mode = false
        @capture_events = false
        @log_level = :info
        @captured_events = []
        @event_mutex = Mutex.new
        @performance_metrics = {}
        @performance_mutex = Mutex.new
      end

      # Enable debug mode with event capture
      def enable_debug_mode
        @debug_mode = true
        @capture_events = true
        @log_level = :debug
        log_debug('Debug mode enabled')
      end

      # Disable debug mode
      def disable_debug_mode
        @debug_mode = false
        @capture_events = false
        @log_level = :info
        clear_captured_events
        log_debug('Debug mode disabled')
      end

      # Execute block in test mode with event capture
      def test_mode(&block)
        previous_debug_mode = @debug_mode
        previous_capture_events = @capture_events

        enable_debug_mode
        clear_captured_events

        result = block.call

        disable_debug_mode
        @debug_mode = previous_debug_mode
        @capture_events = previous_capture_events

        result
      end

      # Get captured events
      def captured_events
        @event_mutex.synchronize do
          @captured_events.dup
        end
      end

      # Clear captured events
      def clear_captured_events
        @event_mutex.synchronize do
          @captured_events.clear
        end
      end

      # Capture an event for debugging
      def capture_event(event)
        return unless @capture_events

        @event_mutex.synchronize do
          @captured_events << {
            event: event.to_h,
            captured_at: Time.now.utc,
            thread_id: Thread.current.object_id
          }
        end

        log_debug("Event captured: #{event.event_type} - #{event.action}")
      end

      # Get performance metrics
      def performance_metrics
        @performance_mutex.synchronize do
          @performance_metrics.dup
        end
      end

      # Record performance metric
      def record_metric(name, value, tags = {})
        return unless @debug_mode

        @performance_mutex.synchronize do
          @performance_metrics[name] ||= []
          @performance_metrics[name] << {
            value: value,
            timestamp: Time.now.utc,
            tags: tags
          }
        end
      end

      # Log debug message
      def log_debug(message, data = nil)
        return unless @debug_mode

        log_entry = {
          timestamp: Time.now.utc,
          level: 'DEBUG',
          message: message,
          thread_id: Thread.current.object_id
        }

        log_entry[:data] = data if data
        log_entry[:correlation] = CorrelationManager.current_context&.to_h

        puts format_log_entry(log_entry)
      end

      # Log info message
      def log_info(message, data = nil)
        return unless @log_level == :debug || @log_level == :info

        log_entry = {
          timestamp: Time.now.utc,
          level: 'INFO',
          message: message,
          thread_id: Thread.current.object_id
        }

        log_entry[:data] = data if data

        puts format_log_entry(log_entry)
      end

      # Log warning message
      def log_warning(message, data = nil)
        log_entry = {
          timestamp: Time.now.utc,
          level: 'WARN',
          message: message,
          thread_id: Thread.current.object_id
        }

        log_entry[:data] = data if data

        puts format_log_entry(log_entry)
      end

      # Log error message
      def log_error(message, error = nil, data = nil)
        log_entry = {
          timestamp: Time.now.utc,
          level: 'ERROR',
          message: message,
          thread_id: Thread.current.object_id
        }

        if error
          log_entry[:error] = {
            class: error.class.name,
            message: error.message,
            backtrace: error.backtrace&.first(5)
          }
        end

        log_entry[:data] = data if data

        puts format_log_entry(log_entry)
      end

      private

      def format_log_entry(entry)
        timestamp = entry[:timestamp].strftime('%Y-%m-%d %H:%M:%S.%3N')
        level = entry[:level].ljust(5)
        message = entry[:message]
        thread_id = entry[:thread_id]

        formatted = "[#{timestamp}] #{level} [Thread-#{thread_id}] #{message}"

        formatted += " | Correlation: #{entry[:correlation][:correlation_id]}" if entry[:correlation]

        formatted += " | Data: #{entry[:data].to_json}" if entry[:data]

        formatted += " | Error: #{entry[:error][:class]}: #{entry[:error][:message]}" if entry[:error]

        formatted
      end
    end

    # Initialize debug tools
    initialize
  end

  # TestHelpers provides RSpec-style test helpers for validating
  # event flows and correlation chains in tests.
  #
  # @example Using test helpers
  #   RSpec.describe "User flow" do
  #     it "tracks complete user journey" do
  #       EzlogsRubyAgent.test_mode do
  #         # Perform actions
  #         events = EzlogsRubyAgent.captured_events
  #         expect(events).to have_correlation_flow
  #         expect(events).to include_http_request
  #         expect(events).to include_data_change
  #       end
  #     end
  #   end
  module TestHelpers
    # RSpec matchers for event validation
    module Matchers
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
    end

    # Matcher for correlation flow validation
    class CorrelationFlowMatcher
      def matches?(events)
        return false if events.empty?

        # Check that all events have the same correlation ID
        correlation_ids = events.map { |e| e[:event][:correlation][:correlation_id] }.compact.uniq
        correlation_ids.size == 1
      end

      def failure_message
        'Expected events to have a consistent correlation flow'
      end

      def failure_message_when_negated
        'Expected events to not have a consistent correlation flow'
      end
    end

    # Matcher for HTTP request validation
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

    # Matcher for data change validation
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

    # Matcher for job execution validation
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

    # Matcher for event count validation
    class EventCountMatcher
      def initialize(expected_count)
        @expected_count = expected_count
      end

      def matches?(events)
        events.size == @expected_count
      end

      def failure_message
        "Expected #{@expected_count} events, but got #{events.size}"
      end

      def failure_message_when_negated
        "Expected not to have #{@expected_count} events"
      end
    end

    # Matcher for correlation ID validation
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
  end

  # PerformanceMonitor provides real-time performance monitoring
  # and metrics collection for the EzlogsRubyAgent system.
  #
  # @example Using performance monitor
  #   monitor = PerformanceMonitor.new
  #   monitor.start_timing('event_processing')
  #   # ... process event
  #   monitor.end_timing('event_processing')
  class PerformanceMonitor
    def initialize
      @timings = {}
      @counters = {}
      @gauges = {}
      @mutex = Mutex.new
    end

    # Start timing a named operation
    def start_timing(name)
      @mutex.synchronize do
        @timings[name] = Time.now
      end
    end

    # End timing and record duration
    def end_timing(name)
      @mutex.synchronize do
        start_time = @timings.delete(name)
        return unless start_time

        duration = (Time.now - start_time).to_f
        record_timing(name, duration)
      end
    end

    # Record a timing measurement
    def record_timing(name, duration)
      @mutex.synchronize do
        @timings[name] ||= []
        @timings[name] << {
          duration: duration,
          timestamp: Time.now.utc
        }
      end
    end

    # Increment a counter
    def increment_counter(name, value = 1)
      @mutex.synchronize do
        @counters[name] ||= 0
        @counters[name] += value
      end
    end

    # Set a gauge value
    def set_gauge(name, value)
      @mutex.synchronize do
        @gauges[name] = {
          value: value,
          timestamp: Time.now.utc
        }
      end
    end

    # Get all metrics
    def metrics
      @mutex.synchronize do
        {
          timings: calculate_timing_stats,
          counters: @counters.dup,
          gauges: @gauges.dup
        }
      end
    end

    # Get timing statistics
    def calculate_timing_stats
      stats = {}

      @timings.each do |name, measurements|
        next unless measurements.is_a?(Array) && measurements.any?

        durations = measurements.map { |m| m[:duration] }
        stats[name] = {
          count: durations.size,
          min: durations.min,
          max: durations.max,
          avg: durations.sum / durations.size,
          p95: percentile(durations, 95),
          p99: percentile(durations, 99)
        }
      end

      stats
    end

    private

    def percentile(values, percentile)
      sorted = values.sort
      index = (percentile / 100.0 * (sorted.size - 1)).ceil
      sorted[index]
    end
  end
end
