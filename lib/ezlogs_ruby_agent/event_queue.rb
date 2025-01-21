module EzlogsRubyAgent
  class EventQueue
    include Singleton

    def initialize
      @queue = Queue.new
    end

    def add(event)
      event[:request_id] ||= Thread.current[:ezlogs_request_id]
      @queue << event

      process_queue if @queue.size >= EzlogsRubyAgent.config.batch_size
    end

    def process_queue
      return if @queue.empty?

      events = []
      while !@queue.empty?
        events << @queue.pop
      end

      send_to_server(events)
    end

    def send_to_server(events)
      Thread.new do
        uri = URI(EzlogsRubyAgent.config.endpoint_url)
        Net::HTTP.post(uri, events.to_json, "Content-Type" => "application/json")
      end
    end
  end
end
