module EzlogsRubyAgent
  class EventQueue
    @queue = Queue.new

    def self.add(event)
      @queue << event
      process_queue if @queue.size >= EzlogsRubyAgent.config.batch_size
    end

    def self.process_queue
      return if @queue.empty?

      events = []
      while !@queue.empty?
        events << @queue.pop
      end

      send_to_server(events)
    end

    def self.send_to_server(events)
      Thread.new do
        uri = URI(EzlogsRubyAgent.config.endpoint_url)
        Net::HTTP.post(uri, events.to_json, "Content-Type" => "application/json")
      end
    end
  end
end
