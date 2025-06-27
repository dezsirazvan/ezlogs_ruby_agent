require 'ezlogs_ruby_agent/correlation_manager'

module EzlogsRubyAgent
  # Sidekiq client middleware to capture correlation context when jobs are enqueued
  # This ensures jobs inherit the correlation ID from the HTTP request that triggered them
  class JobEnqueueMiddleware
    def call(worker_class, job, queue, redis_pool)
      # Capture current correlation context
      current_context = CorrelationManager.current_context

      begin
        if current_context
          # Pass the complete hierarchical correlation context to the job
          correlation_data = {
            correlation_id: current_context.correlation_id,
            primary_correlation_id: current_context.primary_correlation_id,
            flow_id: current_context.flow_id,
            parent_flow_id: current_context.parent_flow_id,
            session_id: current_context.session_id,
            request_id: current_context.request_id,
            parent_event_id: current_context.parent_event_id,
            depth: current_context.depth,
            chain: current_context.chain,
            metadata: current_context.metadata
          }.compact

          # Safely add correlation data to job hash
          add_correlation_data_to_job(job, '_correlation_data', correlation_data)
          # Also set the primary_correlation_id directly for backward compatibility
          add_correlation_data_to_job(job, 'correlation_id', current_context.primary_correlation_id)
        else
          # No current context - generate new correlation ID with proper format
          correlation_id = CorrelationManager::Context.new.correlation_id
          correlation_data = {
            correlation_id: correlation_id,
            primary_correlation_id: correlation_id,
            metadata: {
              source: 'job_enqueue',
              enqueued_at: Time.now.utc.iso8601(3)
            }
          }

          add_correlation_data_to_job(job, 'correlation_id', correlation_id)
          add_correlation_data_to_job(job, '_correlation_data', correlation_data)
        end
      rescue FrozenError => e
        warn "[EzlogsRubyAgent] Cannot add correlation data to frozen job hash: #{e.message}"
      rescue StandardError => e
        warn "[EzlogsRubyAgent] Error adding correlation data to job: #{e.message}"
      end

      yield
    end

    private

    # Safely add data to job hash, handling frozen hashes
    def add_correlation_data_to_job(job, key, value)
      job[key] = value
    rescue FrozenError
      # Job hash is frozen, cannot modify it
      # This can happen in certain Sidekiq configurations
      warn "[EzlogsRubyAgent] Cannot modify frozen job hash for key '#{key}'"
    end
  end
end
