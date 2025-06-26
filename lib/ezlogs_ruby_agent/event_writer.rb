require 'socket'
require 'json'
require 'digest'
require 'timeout'
require 'set'
require 'ostruct'
require 'ezlogs_ruby_agent/event_pool'

module EzlogsRubyAgent
  class EventWriter
    # Performance constants following workspace rules
    BATCH_SIZE = 100
    MAX_BUFFER_SIZE = 1000
    FLUSH_INTERVAL = 5.0
    MAX_BATCH_WAIT_TIME = 1.0
    MAX_EVENT_SIZE = 1024 * 1024 # 1MB
    SHUTDOWN_TIMEOUT = 5.0

    # Pre-allocated string constants to avoid allocations
    ERROR_TYPES = {
      buffer_full: '[EzlogsRubyAgent] Buffer full, dropping event'.freeze,
      processing_error: '[EzlogsRubyAgent] Failed to process event'.freeze,
      delivery_error: '[EzlogsRubyAgent] Failed to send batch'.freeze,
      shutdown_error: '[EzlogsRubyAgent] Error during shutdown'.freeze,
      writer_thread_error: '[EzlogsRubyAgent] Writer thread error'.freeze,
      flush_error: '[EzlogsRubyAgent] Error during flush'.freeze,
      no_events: 'No events to deliver'.freeze
    }.freeze

    def initialize
      @config = EzlogsRubyAgent.config
      @delivery_engine = EzlogsRubyAgent.delivery_engine
      @event_processor = EzlogsRubyAgent.processor

      # Thread-safe queue with bounded size for back-pressure
      @queue = SizedQueue.new(MAX_BUFFER_SIZE)

      # Performance metrics with thread-safe access
      @metrics = initialize_metrics
      @metrics_mutex = Mutex.new

      # Background processing thread
      @writer_thread = nil
      @shutdown_requested = false
      @shutdown_mutex = Mutex.new

      # String cache for repeated values (performance optimization)
      @string_cache = {}
      @string_cache_mutex = Mutex.new

      # Batch processing buffer (reused to minimize allocations)
      @batch_buffer = Array.new(BATCH_SIZE)

      start_writer_thread
      setup_shutdown_handler
    end

    # Thread-safe event logging with performance tracking
    def log(event)
      return if shutdown_requested?

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        processed_event = process_event(event)

        if processed_event
          enqueue_processed_event(processed_event)
          record_metric(:events_received, 1)
          record_latency_metric(start_time)
        else
          record_metric(:events_filtered, 1)
        end
      rescue ThreadError
        record_metric(:events_dropped, 1)
        warn_once(:buffer_full, ERROR_TYPES[:buffer_full])
      rescue StandardError => e
        record_metric(:processing_errors, 1)
        warn "#{ERROR_TYPES[:processing_error]}: #{e.message}"
      end
    end

    # Get current performance metrics
    def metrics
      @metrics_mutex.synchronize { @metrics.dup }
    end

    # Get comprehensive health status
    def health_status
      current_metrics = metrics
      {
        queue_size: @queue.size,
        max_buffer: MAX_BUFFER_SIZE,
        buffer_utilization: calculate_buffer_utilization,
        thread_alive: writer_thread_alive?,
        shutdown_requested: shutdown_requested?,
        metrics: current_metrics,
        performance: {
          avg_latency_ms: current_metrics[:total_latency_ms] / [current_metrics[:events_received], 1].max,
          throughput_per_sec: calculate_throughput(current_metrics)
        }
      }
    end

    # Graceful shutdown with timeout
    def shutdown
      @shutdown_mutex.synchronize do
        return if @shutdown_requested

        @shutdown_requested = true
      end

      begin
        # Signal shutdown and wait for thread to finish
        if @writer_thread&.alive?
          @writer_thread.join(SHUTDOWN_TIMEOUT)
          @writer_thread.kill if @writer_thread.alive?
        end

        # Final flush of remaining events
        flush_remaining_events
      rescue StandardError => e
        warn "#{ERROR_TYPES[:shutdown_error]}: #{e.message}"
      end
    end

    private

    def initialize_metrics
      {
        events_received: 0,
        events_processed: 0,
        events_delivered: 0,
        events_dropped: 0,
        events_filtered: 0,
        events_failed: 0,
        batches_sent: 0,
        processing_errors: 0,
        delivery_errors: 0,
        total_latency_ms: 0.0,
        start_time: Process.clock_gettime(Process::CLOCK_MONOTONIC)
      }
    end

    def process_event(event)
      case event
      when UniversalEvent
        process_universal_event(event)
      when Hash
        process_event_hash(event)
      else
        warn "#{ERROR_TYPES[:processing_error]}: Unsupported event type #{event.class}"
        nil
      end
    end

    def process_universal_event(event)
      # Validate event size to prevent memory issues
      return nil if event_too_large?(event)

      # Process through EventProcessor (includes sanitization)
      processed = @event_processor.process(event)

      if processed&.dig(:event_type) && processed.dig(:action)
        record_metric(:events_processed, 1)

        # Capture for debugging if enabled
        capture_debug_event(processed) if EzlogsRubyAgent.debug_mode

        processed
      else
        nil # Event was filtered or invalid
      end
    end

    def process_event_hash(event_hash)
      # Convert hash to UniversalEvent with proper error handling
      universal_event = create_universal_event_from_hash(event_hash)
      process_universal_event(universal_event)
    rescue StandardError => e
      warn "#{ERROR_TYPES[:processing_error]} from hash: #{e.message}"
      create_error_event(e, event_hash)
    end

    def create_universal_event_from_hash(event_hash)
      # Extract fields with performance-optimized string interning
      event_type = intern_string(extract_field(event_hash, 'event_type', 'unknown.event'))
      action = intern_string(extract_field(event_hash, 'action', 'unknown'))
      actor = event_hash['actor'] || event_hash[:actor] || { type: 'system', id: 'unknown' }

      # Optional fields
      subject = event_hash['subject'] || event_hash[:subject]
      metadata = event_hash['metadata'] || event_hash[:metadata] || {}
      correlation_id = event_hash['correlation_id'] || event_hash[:correlation_id]
      timing = event_hash['timing'] || event_hash[:timing]
      correlation_context = event_hash['correlation_context'] || event_hash[:correlation_context]
      payload = event_hash['payload'] || event_hash[:payload]
      event_id = event_hash['event_id'] || event_hash[:event_id]

      UniversalEvent.new(
        event_type: event_type,
        action: action,
        actor: actor,
        subject: subject,
        metadata: metadata,
        correlation_id: correlation_id,
        timing: timing,
        correlation_context: correlation_context,
        payload: payload,
        event_id: event_id
      )
    end

    def create_error_event(error, original_data)
      UniversalEvent.new(
        event_type: 'system.error',
        action: 'event_creation_failed',
        actor: { type: 'system', id: 'event_writer' },
        metadata: {
          error: error.message,
          error_class: error.class.name,
          original_data_type: original_data.class.name
        }
      )
    end

    def enqueue_processed_event(processed_event)
      @queue << processed_event
    end

    def start_writer_thread
      @writer_thread = Thread.new do
        Thread.current.name = 'EzlogsRubyAgent::EventWriter'
        writer_thread_loop
      end
    end

    def writer_thread_loop
      batch_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      loop do
        break if shutdown_requested?

        begin
          batch = collect_batch(batch_start_time)

          if batch.any?
            send_batch(batch)
            batch_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          else
            # Brief sleep if no events to prevent busy waiting
            sleep(0.1)
          end
        rescue StandardError => e
          record_metric(:processing_errors, 1)
          warn "#{ERROR_TYPES[:writer_thread_error]}: #{e.message}"
          sleep(1) # Pause before retry to avoid tight error loops
        end
      end
    rescue StandardError => e
      warn "#{ERROR_TYPES[:writer_thread_error]} (fatal): #{e.message}"
    end

    def collect_batch(batch_start_time)
      @batch_buffer.clear
      current_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Collect first event (blocking with timeout)
      first_event = nil
      begin
        Timeout.timeout(MAX_BATCH_WAIT_TIME) do
          first_event = @queue.pop
        end
      rescue Timeout::Error
        return @batch_buffer # Return empty batch if timeout
      end

      return @batch_buffer unless first_event

      @batch_buffer << first_event

      # Collect additional events for batching (non-blocking)
      while @batch_buffer.size < BATCH_SIZE
        break if shutdown_requested?

        begin
          event = @queue.pop(true) # Non-blocking
          @batch_buffer << event
        rescue ThreadError
          break # No more events available
        end

        # Force send if batch has been waiting too long
        break if current_time - batch_start_time > FLUSH_INTERVAL
      end

      @batch_buffer.dup # Return copy to avoid modification during processing
    end

    def send_batch(events)
      return if events.empty?

      begin
        # Validate batch before sending
        valid_events = events.select { |event| valid_event?(event) }

        if valid_events.empty?
          warn ERROR_TYPES[:no_events]
          record_metric(:events_failed, events.size)
          return
        end

        # Send via DeliveryEngine
        delivery_result = @delivery_engine.deliver_batch(valid_events)

        if delivery_result.success?
          record_metric(:events_delivered, valid_events.size)
          record_metric(:batches_sent, 1)
        else
          record_metric(:events_failed, valid_events.size)
          record_metric(:delivery_errors, 1)
          warn "#{ERROR_TYPES[:delivery_error]}: #{delivery_result.error}"
        end
      rescue StandardError => e
        record_metric(:events_failed, events.size)
        record_metric(:delivery_errors, 1)
        warn "#{ERROR_TYPES[:delivery_error]}: #{e.class}: #{e.message}"
      end
    end

    def flush_remaining_events
      return unless @queue && !@queue.empty?

      events = []

      # Drain all remaining events
      until @queue.empty?
        begin
          events << @queue.pop(true)
          break if events.size >= BATCH_SIZE
        rescue ThreadError
          break
        end
      end

      send_batch(events) unless events.empty?
    rescue StandardError => e
      warn "#{ERROR_TYPES[:flush_error]}: #{e.message}"
    end

    def setup_shutdown_handler
      at_exit { shutdown }
    end

    # Performance optimization: String interning for repeated values
    def intern_string(str)
      return str unless str.is_a?(String)

      @string_cache_mutex.synchronize do
        @string_cache[str] ||= str.dup.freeze
      end
    end

    def extract_field(hash, field_name, default)
      hash[field_name] || hash[field_name.to_sym] || default
    end

    def event_too_large?(event)
      begin
        event_size = JSON.generate(event.to_h).bytesize
        if event_size > MAX_EVENT_SIZE
          record_metric(:events_dropped, 1)
          warn "#{ERROR_TYPES[:processing_error]}: Event too large (#{event_size} bytes)"
          return true
        end
      rescue StandardError => e
        warn "#{ERROR_TYPES[:processing_error]}: Failed to calculate event size: #{e.message}"
        return true
      end

      false
    end

    def valid_event?(event)
      event.is_a?(Hash) &&
        event[:event_type] &&
        event[:action] &&
        event[:actor]
    end

    def capture_debug_event(processed_event)
      return unless defined?(EzlogsRubyAgent::DebugTools)

      begin
        debug_event = OpenStruct.new(processed_event)
        EzlogsRubyAgent::DebugTools.capture_event(debug_event)
      rescue StandardError => e
        warn "Debug capture failed: #{e.message}"
      end
    end

    def record_metric(metric, increment = 1)
      @metrics_mutex.synchronize do
        @metrics[metric] = (@metrics[metric] || 0) + increment
      end
    end

    def record_latency_metric(start_time)
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      latency_ms = (end_time - start_time) * 1000

      @metrics_mutex.synchronize do
        @metrics[:total_latency_ms] += latency_ms
      end
    end

    def shutdown_requested?
      @shutdown_mutex.synchronize { @shutdown_requested }
    end

    def writer_thread_alive?
      @writer_thread&.alive? || false
    end

    def calculate_buffer_utilization
      (@queue.size.to_f / MAX_BUFFER_SIZE * 100).round(2)
    end

    def calculate_throughput(metrics)
      elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - metrics[:start_time]
      return 0.0 if elapsed_time <= 0

      (metrics[:events_delivered] / elapsed_time).round(2)
    end

    # Optimize warning messages to avoid repeated warnings
    def warn_once(key, message)
      @warned_messages ||= Set.new

      return if @warned_messages.include?(key)

      warn message
      @warned_messages << key
    end
  end
end
