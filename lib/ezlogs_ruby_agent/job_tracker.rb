module EzlogsRubyAgent
  module JobTracker
    def perform(*args)
      return unless trackable_job?
      request_id = Thread.current[:ezlogs_request_id] || args.extract_options!.dig(:request_id)

      start_time = Time.current
      super
      end_time = Time.current

      EzlogsRubyAgent::EventQueue.add({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "completed",
        request_id: request_id,
        duration: (end_time - start_time).to_f,
        timestamp: Time.current
      })
    rescue => e
      EzlogsRubyAgent::EventQueue.add({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "failed",
        request_id: request_id,
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
