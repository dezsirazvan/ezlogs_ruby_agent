module EzlogsRubyAgent
  class EventQueue
    include Singleton

    def initialize
      @buffer = []
      @mutex = Mutex.new
    end

    def add(event)
      event[:request_id] ||= Thread.current[:ezlogs_request_id]

      @mutex.synchronize do
        @buffer << event
      end

      if @buffer.size >= EzlogsRubyAgent.config.batch_size
        flush
      end
    end

    def flush
      events_to_send = nil

      @mutex.synchronize do
        events_to_send = @buffer.dup
        @buffer.clear
      end

      enqueue_job(events_to_send) if events_to_send.any?
    end

    private

    def enqueue_job(events)
      events_json = events.to_json

      if EzlogsRubyAgent.config.job_adapter == :sidekiq
        EzlogsRubyAgent::EventSenderJob.set(queue: :ezlogs_events).perform_async(events_json)
      else
        EzlogsRubyAgent::EventSenderJob.perform_later(events_json)
      end
    end
end
end
