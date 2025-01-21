module EzlogsRubyAgent
  module JobTracker
    def perform(*args)
      return unless trackable_job?

      start_time = Time.current
      super
      end_time = Time.current

      EzlogsRubyAgent::EventQueue.add({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "completed",
        duration: (end_time - start_time).to_f,
        timestamp: Time.current
      })
    rescue => e
      EzlogsRubyAgent::EventQueue.add({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "failed",
        error: e.message,
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
  end
end
