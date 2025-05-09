require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'

module EzlogsRubyAgent
  class SidekiqJobTracker
    def call(worker, job, _queue)
      config = EzlogsRubyAgent.config
      job_name = worker.class.name
      correlation_id = job['correlation_id'] || Thread.current[:correlation_id] || SecureRandom.uuid
      return yield unless trackable_job?(job_name, config)

      start_time = Time.current
      resource_id = extract_resource_id_from_job(job)

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
        event_data = build_event_data(
          job_name, job['args'],
          status,
          error_message,
          (end_time - start_time).to_f,
          resource_id,
          correlation_id
        )

        EzlogsRubyAgent.writer.log(event_data)
      end
    end

    private

    def extract_resource_id_from_job(job)
      job['args'].first[:id] if job['args'].first.is_a?(Hash)
    end

    def trackable_job?(job_name, config)
      resource_match = config.resources_to_track.empty? ||
                       config.resources_to_track.map(&:downcase).any? do |resource|
                         job_name.downcase.include?(resource.downcase)
                       end
      excluded_match = config.exclude_resources.map(&:downcase).any? do |resource|
        job_name.downcase.include?(resource.downcase)
      end

      resource_match && !excluded_match
    end

    def build_event_data(job_name, args, status, error_message, duration, resource_id, correlation_id) # rubocop:disable Metrics/ParameterLists
      {
        event_id: SecureRandom.uuid,
        correlation_id: correlation_id,
        event_type: 'background_job',
        resource: 'Job',
        action: job_name,
        actor: ActorExtractor.extract_actor(nil),
        timestamp: Time.current.to_s,
        metadata: {
          'job_name' => job_name,
          'arguments' => args,
          'status' => status,
          'error_message' => error_message,
          'duration' => duration
        },
        resource_id: resource_id,
        duration: duration
      }
    end
  end
end
