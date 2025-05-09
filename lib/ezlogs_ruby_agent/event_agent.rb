require 'json'
require 'set'
require 'ezlogs_ruby_agent/protobuf/event_pb'

module EzlogsRubyAgent
  class EventAgent
    PROCESSED_EVENT_FILE = 'processed_events.json'.freeze
    PROCESSED_EVENT_IDS = Set.new

    def self.load_processed_event_ids
      return unless File.exist?(PROCESSED_EVENT_FILE)

      JSON.parse(File.read(PROCESSED_EVENT_FILE)).each do |event_id|
        PROCESSED_EVENT_IDS.add(event_id)
      end
    end

    def self.save_processed_event_ids
      File.write(PROCESSED_EVENT_FILE, JSON.pretty_generate(PROCESSED_EVENT_IDS.to_a))
    end

    # This starts the agent in a background thread.
    def self.start
      Thread.new do
        loop do
          read_and_process_events
          sleep(5) # Sleep for 5 seconds before checking again
        end
      end
    end

    def self.read_and_process_events
      load_processed_event_ids

      log_files = Dir.glob('events.log*').sort_by { |f| File.mtime(f) }

      log_files.each do |file|
        process_log_file(file)
      end

      save_processed_event_ids
    end

    def self.process_log_file(file)
      File.open(file, 'r') do |f|
        f.each_line do |line|
          process_event(line)
        end
      end
    end

    def self.process_event(event_data)
      event = Ezlogs::Event.decode(event_data)

      return if PROCESSED_EVENT_IDS.include?(event.event_id)

      PROCESSED_EVENT_IDS.add(event.event_id)

      handle_event(event)
    end

    def self.handle_event(event)
      send_event_to_server(event)
    end

    def self.send_event_to_server(event)
      uri = URI.parse('https://your-server.com/endpoint')
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/x-protobuf'
      request.body = event.to_proto

      response = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(request)
      end

      puts "Sent event #{event.event_id} to server with response: #{response.code}"
    end
  end
end

EzlogsRubyAgent::EventAgent.start
