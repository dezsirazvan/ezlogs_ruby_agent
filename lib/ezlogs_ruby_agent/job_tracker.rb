require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'

module EzlogsRubyAgent
  module JobTracker
    def perform(*args)
      Thread.current[:correlation_id] || SecureRandom.uuid
      return unless trackable_job?

      start_time = Time.now
      resource_id = extract_resource_id_from_args(args)

      super

      end_time = Time.now

      begin
        event = UniversalEvent.new(
          event_type: 'background_job',
          resource: 'Job',
          resource_id: resource_id,
          action: self.class.name,
          actor: ActorExtractor.extract_actor(nil),
          timestamp: start_time,
          metadata: {
            "job_name" => self.class.name,
            "arguments" => args,
            "status" => "completed",
            "error_message" => nil,
            "duration" => (end_time - start_time).to_f
          },
          duration: (end_time - start_time).to_f
        )

        EzlogsRubyAgent.writer.log(event.to_h)
      rescue StandardError => e
        warn "[Ezlogs] failed to create job event: #{e.message}"
      end
    rescue => e
      begin
        event = UniversalEvent.new(
          event_type: 'background_job',
          resource: 'Job',
          resource_id: resource_id,
          action: self.class.name,
          actor: ActorExtractor.extract_actor(nil),
          timestamp: start_time,
          metadata: {
            "job_name" => self.class.name,
            "arguments" => args,
            "status" => "failed",
            "error_message" => e.message,
            "duration" => 0
          },
          duration: 0
        )

        EzlogsRubyAgent.writer.log(event.to_h)
      rescue StandardError => log_error
        warn "[Ezlogs] failed to create failed job event: #{log_error.message}"
      end
      raise e
    end

    private

    def extract_resource_id_from_args(args)
      args.first[:id] if args.first.is_a?(Hash)
    end

    def trackable_job?
      config = EzlogsRubyAgent.config
      job_name = self.class.name.downcase

      resource_match = config.resources_to_track.empty? ||
                       config.resources_to_track.map(&:downcase).any? do |resource|
                         job_name.include?(resource.downcase)
                       end
      excluded_match = config.exclude_resources.map(&:downcase).any? { |resource| job_name.include?(resource.downcase) }

      resource_match && !excluded_match
    end
  end
end
