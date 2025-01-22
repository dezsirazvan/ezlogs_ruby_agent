module EzlogsRubyAgent
  class SidekiqJobTracker
    def call(worker, job, _queue)
      config = EzlogsRubyAgent.config
      job_name = worker.class.name
      return yield unless trackable_job?(job_name, config)

      start_time = Time.current
      correlation_id = job['correlation_id'] || Thread.current[:correlation_id] || SecureRandom.uuid
      resource_id = extract_resource_id_from_job(job)
      actor = EzlogsRubyAgent::ActorExtractor.extract_actor

      begin
        yield
        status = 'completed'
        error_message = nil
      rescue StandardError => e
        status = 'failed'
        error_message = e.message
        raise e
      ensure
        end_time = Time.current
        add_event({
          type: 'background_job',
          job_name: job_name,
          arguments: job['args'],
          status: status,
          error_message: error_message,
          duration: (end_time - start_time).to_f,
          correlation_id: correlation_id,
          resource_id: resource_id,
          actor: actor,
          timestamp: Time.current
        })
      end
    end

    private

    def extract_resource_id_from_job(job)
      job['args'].first[:id] if job['args'].first.is_a?(Hash)
    end

    def trackable_job?(job_name, config)
      resource_match = config.resources_to_track.empty? ||
                    config.resources_to_track.any? { |resource| job_name.downcase.include?(resource) }
      excluded_match = config.exclude_resources.any? { |resource| job_name.downcase.include?(resource) }

      resource_match && !excluded_match
    end

    def add_event(event_data)
      EzlogsRubyAgent::EventQueue.instance.add(event_data)
    end
  end
end
