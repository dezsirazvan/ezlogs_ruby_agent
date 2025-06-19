require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'

module EzlogsRubyAgent
  class SidekiqJobTracker
    def call(worker, job, _queue)
      config = EzlogsRubyAgent.config
      job_name = worker.class.name
      correlation_id = job['correlation_id'] || Thread.current[:correlation_id] || SecureRandom.uuid
      return yield unless trackable_job?(job_name, config)

      start_time = Time.now
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
        end_time = Time.now

        begin
          event = UniversalEvent.new(
            event_type: 'background_job',
            resource: 'Job',
            resource_id: resource_id,
            action: job_name,
            actor: ActorExtractor.extract_actor(nil),
            timestamp: start_time,
            metadata: {
              'job_name' => job_name,
              'arguments' => job['args'],
              'status' => status,
              'error_message' => error_message,
              'duration' => (end_time - start_time).to_f
            },
            duration: (end_time - start_time).to_f
          )

          EzlogsRubyAgent.writer.log(event.to_h)
        rescue StandardError => e
          warn "[Ezlogs] failed to create Sidekiq job event: #{e.message}"
        end
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
  end
end
