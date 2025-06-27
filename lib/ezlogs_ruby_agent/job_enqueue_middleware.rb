require 'ezlogs_ruby_agent/correlation_manager'

module EzlogsRubyAgent
  # Sidekiq client middleware to capture correlation context when jobs are enqueued
  # This ensures jobs inherit the correlation ID from the HTTP request that triggered them
  class JobEnqueueMiddleware
    def call(worker_class, job, queue, redis_pool)
      # Capture current correlation context
      current_context = CorrelationManager.current_context

      if current_context
        # Pass the complete correlation context to the job
        job['_correlation_data'] = {
          correlation_id: current_context.correlation_id,
          flow_id: current_context.flow_id,
          session_id: current_context.session_id,
          request_id: current_context.request_id,
          parent_event_id: current_context.parent_event_id,
          metadata: current_context.metadata
        }

        # Also set the correlation_id directly for backward compatibility
        job['correlation_id'] = current_context.correlation_id
      else
        # No current context - generate new correlation ID with proper format
        correlation_id = CorrelationManager::Context.new.correlation_id
        job['correlation_id'] = correlation_id
        job['_correlation_data'] = {
          correlation_id: correlation_id,
          metadata: {
            source: 'job_enqueue',
            enqueued_at: Time.now.utc.iso8601(3)
          }
        }
      end

      yield
    end
  end
end
