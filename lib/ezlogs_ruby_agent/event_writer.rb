require 'ezlogs_ruby_agent/protobuf/event_pb'

module EzlogsRubyAgent
  module EventWriter
    LOG_FILE_PATH = 'events.log'.freeze
    MAX_LOG_SIZE = 10 * 1024 * 1024 # 10 MB

    def self.write_event_to_log(event_data)
      serialized_event = serialize_event(event_data)

      Thread.new do
        rotate_log_file_if_needed

        File.open(LOG_FILE_PATH, 'a') do |file|
          file.write(serialized_event)
        end
      rescue StandardError => e
        Rails.logger.error("Failed to write event to log: #{e.message}")
      end
    end

    def self.serialize_event(event_data)
      event = Ezlogs::Event.new(
        event_id: event_data[:event_id],
        correlation_id: event_data[:correlation_id],
        event_type: event_data[:event_type],
        resource: event_data[:resource],
        action: event_data[:action],
        actor: event_data[:actor],
        timestamp: event_data[:timestamp],
        metadata: event_data[:metadata]
      )

      event.to_proto
    end

    def self.rotate_log_file_if_needed
      return unless File.exist?(LOG_FILE_PATH) && File.size(LOG_FILE_PATH) > MAX_LOG_SIZE

      rotate_log_files
    end

    def self.rotate_log_files
      log_files = Dir.glob('events.log*').sort_by { |f| File.mtime(f) }

      if log_files.size >= 5
        File.delete(log_files.first) # Remove the oldest log file
      end

      return unless File.exist?(LOG_FILE_PATH)

      timestamp = Time.now.strftime('%Y%m%d%H%M%S')
      new_log_file = "events.log.#{timestamp}"
      File.rename(LOG_FILE_PATH, new_log_file)
    end
  end
end
