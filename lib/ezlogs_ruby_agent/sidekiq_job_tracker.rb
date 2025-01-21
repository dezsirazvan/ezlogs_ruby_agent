# frozen_string_literal: true

module EzlogsRubyAgent
  class SidekiqJobTracker
    def call(worker, job, _queue)
      config = EzlogsRubyAgent.config
      job_name = worker.class.name

      return yield unless trackable_job?(job_name, config)

      start_time = Time.current
      request_id = Thread.current[:ezlogs_request_id] || SecureRandom.uuid

      begin
        yield
        status = 'completed'
      rescue StandardError => e
        status = 'failed'
        error = e.message
        raise e
      ensure
        end_time = Time.current
        EzlogsRubyAgent::EventQueue.instance.add({
          type: 'background_job',
          job_name: job_name,
          arguments: job['args'],
          status: status,
          error: error,
          request_id: request_id,
          duration: (end_time - start_time).to_f,
          timestamp: Time.current
        })
      end
    end

    private

    def trackable_job?(job_name, config)
      model_match = config.models_to_track.empty? ||
                    config.models_to_track.any? { |model| job_name.include?(model) }
      excluded_match = config.exclude_models.any? { |model| job_name.include?(model) }

      model_match && !excluded_match
    end
  end
end
