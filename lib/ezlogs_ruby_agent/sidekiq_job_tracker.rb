require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'
require 'ezlogs_ruby_agent/correlation_manager'

module EzlogsRubyAgent
  class SidekiqJobTracker
    def call(worker, job, _queue)
      config = EzlogsRubyAgent.config
      job_name = worker.class.name
      # Restore correlation context from job hash if present
      correlation_data = extract_correlation_data(job)
      correlation_context = CorrelationManager.restore_context(correlation_data)
      return yield unless trackable_job?(job_name, config)

      start_time = Time.now
      resource_id = extract_resource_id_from_job(job)
      status = nil
      error_message = nil
      result = nil

      begin
        result = yield
        status = 'completed'
      rescue StandardError => e
        status = 'failed'
        error_message = e.message
        raise e
      ensure
        end_time = Time.now
        begin
          event = UniversalEvent.new(
            event_type: 'job.execution',
            action: "#{job_name}.#{status}",
            actor: ActorExtractor.extract_actor(worker),
            subject: {
              type: 'job',
              id: job['jid'],
              queue: job['queue'],
              resource: resource_id
            },
            metadata: {
              job_name: job_name,
              arguments: job['args'],
              status: status,
              error_message: error_message,
              result: result,
              duration: (end_time - start_time).to_f,
              retry_count: job['retry_count'],
              scheduled_at: job['at'],
              enqueued_at: job['enqueued_at']
            },
            timestamp: start_time,
            correlation_context: correlation_context
          )
          EzlogsRubyAgent.writer.log(event)
        rescue StandardError => e
          warn "[Ezlogs] failed to create Sidekiq job event: #{e.message}"
        ensure
          CorrelationManager.clear_context
        end
      end
    end

    # Test helper method to build event without executing job
    def build_event(job_hash)
      job_hash['class']&.name || 'UnknownJob'
      resource_id = extract_resource_id_from_job(job_hash)

      UniversalEvent.new(
        event_type: 'sidekiq.job',
        action: 'enqueue',
        actor: {
          type: 'Job',
          id: job_hash['jid']
        },
        subject: {
          type: 'job',
          id: job_hash['jid'],
          queue: job_hash['queue'],
          resource: resource_id
        },
        payload: {
          queue: job_hash['queue'],
          args: job_hash['args']
        },
        correlation_context: CorrelationManager.current_context
      )
    end

    # Test helper method to track job without executing
    def track(job_hash)
      event = build_event(job_hash)
      EzlogsRubyAgent.writer.log(event)
    end

    private

    def extract_correlation_data(job)
      if job.is_a?(Hash) && job['_correlation_data']
        job['_correlation_data']
      elsif job.is_a?(Hash) && job['correlation_id']
        { correlation_id: job['correlation_id'] }
      else
        {}
      end
    end

    def extract_resource_id_from_job(job)
      return unless job['args'] && job['args'].first.is_a?(Hash)

      job['args'].first[:id] || job['args'].first['id']
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
