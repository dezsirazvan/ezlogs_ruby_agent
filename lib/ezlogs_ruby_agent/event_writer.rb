require 'socket'
require 'json'

module EzlogsRubyAgent
  class EventWriter
    def initialize
      config = EzlogsRubyAgent.config
      @host           = config.agent_host
      @port           = config.agent_port
      @flush_interval = config.flush_interval
      @max_buffer     = config.max_buffer_size
      @queue          = SizedQueue.new(@max_buffer)
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
      payload = JSON.generate(events)
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
