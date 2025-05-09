require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'

module EzlogsRubyAgent
  module JobTracker
    def perform(*args)
      correlation_id = Thread.current[:correlation_id] || SecureRandom.uuid
      return unless trackable_job?

      start_time = Time.current
      resource_id = extract_resource_id_from_args(args)

      super

      end_time = Time.current

      event_data = build_event_data(
        "completed", 
        nil, 
        args, 
        (end_time - start_time).to_f, 
        resource_id, 
        correlation_id
      )

      EzlogsRubyAgent::EventWriter.write_event_to_log(event_data)
    rescue => e
      event_data = build_event_data(
        "failed", 
        e.message, 
        args, 
        0, 
        resource_id, 
        correlation_id
      )

      EzlogsRubyAgent::EventWriter.write_event_to_log(event_data)
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

    def build_event_data(status, error_message, args, duration, resource_id, correlation_id) # rubocop:disable Metrics/ParameterLists
      {
        event_id: SecureRandom.uuid,
        correlation_id: correlation_id,
        event_type: 'background_job',
        resource: 'Job',
        action: self.class.name,
        actor: ActorExtractor.extract_actor(nil),
        timestamp: Time.current.to_s,
        metadata: {
          "job_name" => self.class.name,
          "arguments" => args,
          "status" => status,
          "error_message" => error_message,
          "duration" => duration
        },
        resource_id: resource_id,
        duration: duration
      }
    end
  end
end
