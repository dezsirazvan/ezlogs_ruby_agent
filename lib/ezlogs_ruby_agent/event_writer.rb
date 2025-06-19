require 'socket'
require 'json'
require 'ezlogs_ruby_agent/event_pool'

module EzlogsRubyAgent
  class EventWriter
    def initialize
      config = EzlogsRubyAgent.config
      @flush_interval = config.flush_interval
      @max_buffer = config.max_buffer_size
      @queue = SizedQueue.new(@max_buffer)
      @delivery_engine = EzlogsRubyAgent.delivery_engine
      @event_processor = EzlogsRubyAgent.processor
      @batch_processor = BatchProcessor.new(
        batch_size: config.performance.batch_size,
        max_batch_size: config.performance.max_batch_size,
        compression_threshold: config.performance.compression_threshold
      )
      @metrics = {
        events_received: 0,
        events_processed: 0,
        events_delivered: 0,
        events_failed: 0,
        batches_sent: 0,
        processing_errors: 0,
        delivery_errors: 0
      }
      @metrics_mutex = Mutex.new

      start_writer_thread
    end

    # Thread-safe enqueue with performance tracking
    def log(event)
      if event.is_a?(UniversalEvent)
        # Process UniversalEvent directly
        process_and_enqueue(event)
      else
        # Handle legacy hash format
        enqueue_event_hash(event)
      end
    rescue ThreadError
      record_metric(:events_failed, 1)
      warn '[Ezlogs] Buffer full, dropping event'
    rescue StandardError => e
      record_metric(:processing_errors, 1)
      warn "[Ezlogs] Failed to process event: #{e.message}"
    end

    # Get current metrics
    def metrics
      @metrics_mutex.synchronize do
        @metrics.dup
      end
    end

    # Get health status
    def health_status
      {
        queue_size: @queue.size,
        max_buffer: @max_buffer,
        buffer_utilization: (@queue.size.to_f / @max_buffer * 100).round(2),
        metrics: metrics,
        thread_alive: @writer&.alive?
      }
    end

    # Shutdown the writer gracefully
    def shutdown
      return unless @writer&.alive?

      @writer.kill
      @writer.join(5) # Wait up to 5 seconds for graceful shutdown
      flush_on_exit
    rescue StandardError => e
      warn "[Ezlogs] Error during shutdown: #{e.message}"
    end

    private

    def process_and_enqueue(event)
      # Process the event through EventProcessor
      processed_event = @event_processor.process(event)

      if processed_event
        record_metric(:events_processed, 1)
        @queue << processed_event
        record_metric(:events_received, 1)
      else
        # Event was filtered out by sampling
        record_metric(:events_failed, 1)
      end
    end

    def enqueue_event_hash(event_hash)
      # Convert hash to UniversalEvent for processing
      event = create_universal_event_from_hash(event_hash)
      process_and_enqueue(event)
    end

    def create_universal_event_from_hash(event_hash)
      # Extract required fields with fallbacks
      event_type = event_hash['event_type'] || event_hash[:event_type] || 'unknown.event'
      action = event_hash['action'] || event_hash[:action] || 'unknown'
      actor = event_hash['actor'] || event_hash[:actor] || { type: 'system', id: 'unknown' }

      # Extract optional fields
      subject = event_hash['subject'] || event_hash[:subject]
      metadata = event_hash['metadata'] || event_hash[:metadata] || {}
      timestamp = event_hash['timestamp'] || event_hash[:timestamp]
      correlation_id = event_hash['correlation_id'] || event_hash[:correlation_id]

      UniversalEvent.new(
        event_type: event_type,
        action: action,
        actor: actor,
        subject: subject,
        metadata: metadata,
        timestamp: timestamp,
        correlation_id: correlation_id
      )
    rescue StandardError => e
      warn "[Ezlogs] Failed to create UniversalEvent from hash: #{e.message}"
      # Create a fallback event
      UniversalEvent.new(
        event_type: 'system.error',
        action: 'event_creation_failed',
        actor: { type: 'system', id: 'event_writer' },
        metadata: { error: e.message, original_data: event_hash }
      )
    end

    def start_writer_thread
      @writer = Thread.new do
        loop do
          batch = drain_batch
          send_batch(batch) unless batch.empty?
          sleep @flush_interval
        end
      rescue StandardError => e
        record_metric(:processing_errors, 1)
        warn "[Ezlogs] Writer thread error: #{e.message}"
        retry
      end

      at_exit { flush_on_exit }
    end

    def drain_batch
      events = []
      events << @queue.pop(true) while events.size < @max_buffer
    rescue ThreadError
      events
    end

    def send_batch(events)
      return if events.empty?

      # Process batch through BatchProcessor
      batch_result = @batch_processor.process_batch(events)

      if batch_result[:success]
        # Send via DeliveryEngine
        delivery_result = @delivery_engine.deliver_batch(batch_result[:batch_data][:events])

        if delivery_result.success?
          record_metric(:events_delivered, batch_result[:processed])
          record_metric(:batches_sent, 1)
        else
          record_metric(:events_failed, batch_result[:processed])
          record_metric(:delivery_errors, 1)
          warn "[Ezlogs] Failed to send batch: #{delivery_result.error}"
        end
      else
        record_metric(:events_failed, events.size)
        record_metric(:processing_errors, 1)
        warn "[Ezlogs] Failed to process batch: #{batch_result[:error]}"
      end
    rescue StandardError => e
      record_metric(:events_failed, events.size)
      record_metric(:delivery_errors, 1)
      warn "[Ezlogs] Failed to send batch: #{e.class}: #{e.message}"
    end

    def flush_on_exit
      until @queue.empty?
        batch = drain_batch
        send_batch(batch) unless batch.empty?
      end
    rescue StandardError => e
      warn "[Ezlogs] Error during flush: #{e.message}"
    end

    def record_metric(metric, increment = 1)
      @metrics_mutex.synchronize do
        @metrics[metric] ||= 0
        @metrics[metric] += increment
      end
    end
  end
end
