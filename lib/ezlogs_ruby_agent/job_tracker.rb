module EzlogsRubyAgent
  module JobTracker
    def perform(*args)
      return unless trackable_job?

      start_time = Time.current
      resource_id = extract_resource_id_from_args(args)

      super

      end_time = Time.current

      add_event({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "completed",
        error_message: nil,
        duration: (end_time - start_time).to_f,
        resource_id: resource_id,
        timestamp: Time.current
      })
    rescue => e
      add_event({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "failed",
        error_message: e.message,
        resource_id: resource_id,
        timestamp: Time.current
      })
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
        config.resources_to_track.any? { |resource| job_name.include?(resource.downcase) }
      excluded_match = config.exclude_resources.any? { |resource| job_name.include?(resource.downcase) }

      resource_match && !excluded_match
    end

    def add_event(event_data)
    end
  end
end
