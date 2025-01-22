require 'ezlogs_ruby_agent/event_queue'

module EzlogsRubyAgent
  module JobTracker
    def perform(*args)
      return unless trackable_job?

      start_time = Time.current
      correlation_id = Thread.current[:correlation_id] || SecureRandom.uuid

      super

      end_time = Time.current
      add_event({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "completed",
        duration: (end_time - start_time).to_f,
        correlation_id: correlation_id,
        timestamp: Time.current
      })
    rescue => e
      add_event({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "failed",
        error: e.message,
        correlation_id: correlation_id,
        timestamp: Time.current
      })
      raise e
    end

    private

    def trackable_job?
      config = EzlogsRubyAgent.config
      job_name = self.class.name

      model_match = config.models_to_track.empty? || 
        config.models_to_track.any? { |model| job_name.include?(model) }
      excluded_match = config.exclude_models.any? { |model| job_name.include?(model) }

      model_match && !excluded_match
    end

    def add_event(event_data)
      EzlogsRubyAgent::EventQueue.instance.add(event_data)
    end
  end
end
