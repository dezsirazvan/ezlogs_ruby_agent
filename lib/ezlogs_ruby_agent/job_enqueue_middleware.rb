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

      # Track the job enqueue event
      track_job_enqueue_event(worker_class, job, queue) if EzlogsRubyAgent.config.instrumentation.sidekiq

      yield
    end

    private

    def track_job_enqueue_event(worker_class, job, queue)
      # Create enqueue event to track when jobs are scheduled
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'job.enqueue',
        action: "#{worker_class.name}.enqueue",
        actor: extract_actor,
        subject: {
          type: 'job',
          id: job['jid'],
          queue: queue,
          class: worker_class.name
        },
        metadata: {
          job_class: worker_class.name,
          queue: queue,
          arguments: sanitize_arguments(job['args']),
          scheduled_at: job['at'] ? Time.at(job['at']).iso8601(3) : nil,
          retry_count: job['retry_count'] || 0
        },
        correlation_id: job['correlation_id'],
        correlation_context: CorrelationManager.current_context&.to_h
      )

      EzlogsRubyAgent.writer.log(event)
    rescue StandardError => e
      warn "[EzlogsRubyAgent] Failed to track job enqueue: #{e.message}"
    end

    def extract_actor
      # Try to get actor from current context, fallback to system
      current_context = CorrelationManager.current_context
      if current_context&.metadata&.dig(:actor)
        current_context.metadata[:actor]
      else
        { type: 'system', id: 'job_scheduler' }
      end
    end

    def sanitize_arguments(args)
      return [] unless args.is_a?(Array)

      # Apply basic sanitization to prevent sensitive data in logs
      args.map do |arg|
        case arg
        when Hash
          sanitize_hash(arg)
        when String
          arg.length > 1000 ? "#{arg[0..1000]}..." : arg
        when Array
          arg.size > 10 ? arg.first(10) + ['...'] : arg
        else
          arg
        end
      end
    end

    def sanitize_hash(hash)
      return hash unless hash.is_a?(Hash)

      sanitized = {}
      hash.each do |key, value|
        # Skip potentially sensitive fields
        sanitized[key] = if sensitive_field?(key.to_s)
                           '[REDACTED]'
                         else
                           value
                         end
      end
      sanitized
    end

    def sensitive_field?(field_name)
      sensitive_fields = %w[password token secret api_key authorization]
      sensitive_fields.any? { |field| field_name.downcase.include?(field) }
    end
  end
end
