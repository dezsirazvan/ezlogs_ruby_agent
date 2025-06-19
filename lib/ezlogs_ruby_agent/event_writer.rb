require 'socket'
require 'json'

module EzlogsRubyAgent
  class EventWriter
    def initialize
      config = EzlogsRubyAgent.config
      @flush_interval = config.flush_interval
      @max_buffer = config.max_buffer_size
      @queue = SizedQueue.new(@max_buffer)
      @delivery_engine = EzlogsRubyAgent.delivery_engine
      @event_processor = EzlogsRubyAgent.processor
      start_writer_thread
    end

    # thread-safe enqueue
    def log(event_hash)
      @queue << event_hash
    rescue ThreadError
      warn '[Ezlogs] buffer full, dropping event'
    end

    private

    def start_writer_thread
      @writer = Thread.new do
        loop do
          batch = drain_batch
          send_batch(batch) unless batch.empty?
          sleep @flush_interval
        end
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
      # Process each event through the event processor
      processed_events = events.map do |event_data|
        processed = @event_processor.process(event_data)
        processed ? processed.to_h : nil
      rescue StandardError => e
        warn "[Ezlogs] failed to process event: #{e.message}"
        nil
      end.compact

      return if processed_events.empty?

      # Use the delivery engine to send the batch
      result = @delivery_engine.deliver_batch(processed_events)

      warn "[Ezlogs] failed to send batch: #{result.error}" unless result.success?
    rescue StandardError => e
      warn "[Ezlogs] failed to send batch: #{e.class}: #{e.message}"
    end

    def flush_on_exit
      until @queue.empty?
        batch = drain_batch
        send_batch(batch) unless batch.empty?
      end
    end
  end
end
