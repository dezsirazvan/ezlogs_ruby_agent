require 'socket'
require 'json'

module EzlogsRubyAgent
  class EventWriter
    FLUSH_INTERVAL = EzlogsRubyAgent.config.flush_interval || 1.0
    MAX_BUFFER     = EzlogsRubyAgent.config.max_buffer_size || 5_000

    def initialize(host:, port:)
      @host   = host
      @port   = port
      @queue  = SizedQueue.new(MAX_BUFFER)
      start_writer_thread
    end

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
          sleep FLUSH_INTERVAL
        end
      end

      at_exit { flush_on_exit }
    end

    def drain_batch
      events = []
      events << @queue.pop(true) while events.size < MAX_BUFFER
    rescue ThreadError
      events
    end

    def send_batch(events)
      payload = events.to_json
      TCPSocket.open(@host, @port) do |sock|
        sock.write(payload)
        sock.flush
      end
    rescue StandardError => e
      warn "[Ezlogs] failed to send to agent: #{e.class}: #{e.message}"
    end

    def flush_on_exit
      until @queue.empty?
        batch = drain_batch
        send_batch(batch) unless batch.empty?
      end
    end
  end
end
