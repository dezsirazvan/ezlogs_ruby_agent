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
      EzlogsRubyAgent::Jobs::EventSenderJob.perform_later(events)
    end
  end
end
