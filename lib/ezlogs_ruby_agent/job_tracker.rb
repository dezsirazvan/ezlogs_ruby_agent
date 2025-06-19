require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'
require 'ezlogs_ruby_agent/correlation_manager'

module EzlogsRubyAgent
  module JobTracker
    def perform(*args)
      start_time = Time.now
      
      # Restore correlation context from job arguments
      correlation_data = extract_correlation_data(args)
      correlation_context = CorrelationManager.restore_context(correlation_data)

      # Track job start
      track_job_event('started', args, start_time, nil, correlation_context)

      begin
        # Execute the job
        result = super
        
        end_time = Time.now
        (end_time - start_time).to_f

        # Track successful completion
        track_job_event('completed', args, start_time, end_time, correlation_context, result: result)
        
        result
      rescue => e
        end_time = Time.now
        (end_time - start_time).to_f

        # Track job failure
        track_job_event('failed', args, start_time, end_time, correlation_context, error: e)
        
        raise e
      ensure
        # Clean up correlation context
        CorrelationManager.clear_context
      end
    end

    private

    def track_job_event(status, args, start_time, end_time, _correlation_context, result: nil, error: nil)
      return unless trackable_job?

      begin
        # Create UniversalEvent with proper schema
        event = UniversalEvent.new(
          event_type: 'job.execution',
          action: "#{job_name}.#{status}",
          actor: extract_actor,
          subject: extract_subject(args),
          metadata: build_job_metadata(status, args, start_time, end_time, result, error),
          timestamp: start_time,
          correlation_id: EzlogsRubyAgent::CorrelationManager.current_context&.correlation_id
        )

        # Log the event
        EzlogsRubyAgent.writer.log(event)
      rescue StandardError => e
        warn "[Ezlogs] Failed to create job event: #{e.message}"
      end
    end

    def extract_correlation_data(args)
      return {} unless args.is_a?(Array) && args.any?

      # Look for correlation data in job arguments
      correlation_arg = args.find { |arg| arg.is_a?(Hash) && arg.key?('_correlation_data') }
      return correlation_arg['_correlation_data'] if correlation_arg

      # Fallback to legacy correlation ID
      correlation_arg = args.find { |arg| arg.is_a?(Hash) && arg.key?('correlation_id') }
      return { correlation_id: correlation_arg['correlation_id'] } if correlation_arg

      {}
    end

    def extract_actor
      ActorExtractor.extract_actor(self)
    end

    def extract_subject(args)
      # Extract subject from job arguments
      resource_data = extract_resource_from_args(args)
      
      {
        type: 'job',
        id: job_id,
        queue: queue_name,
        resource: resource_data
      }.compact
    end

    def extract_resource_from_args(args)
      return nil unless args.is_a?(Array) && args.any?

      # Try to extract resource information from arguments
      first_arg = args.first
      
      if first_arg.is_a?(Hash)
        # Look for common resource patterns
        resource_id = first_arg['id'] || first_arg[:id]
        resource_type = first_arg['type'] || first_arg[:type] || first_arg['class'] || first_arg[:class]
        
        if resource_id || resource_type
          return {
            type: resource_type,
            id: resource_id
          }.compact
        end
      elsif first_arg.is_a?(String) || first_arg.is_a?(Integer)
        # Simple ID argument
        return { id: first_arg.to_s }
      end

      nil
    end

    def build_job_metadata(status, args, start_time, end_time, result, error)
      metadata = {
        status: status,
        job_name: job_name,
        job_id: job_id,
        queue: queue_name,
        arguments: sanitize_arguments(args),
        start_time: start_time.iso8601,
        retry_count: extract_retry_count,
        priority: extract_priority
      }

      # Add timing information
      if end_time
        metadata[:end_time] = end_time.iso8601
        metadata[:duration] = (end_time - start_time).to_f
      end

      # Add result information
      metadata[:result] = sanitize_result(result) if result && status == 'completed'

      # Add error information
      if error && status == 'failed'
        metadata[:error] = {
          message: error.message,
          class: error.class.name,
          backtrace: error.backtrace&.first(5)
        }
      end

      # Add job-specific metadata
      metadata.merge!(extract_job_specific_metadata)

      metadata
    end

    def sanitize_arguments(args)
      return [] unless args.is_a?(Array)

      sensitive_fields = EzlogsRubyAgent.config.security.sanitize_fields
      
      args.map do |arg|
        case arg
        when Hash
          sanitize_hash(arg, sensitive_fields)
        when String
          # Check if string contains sensitive data
          if sensitive_fields.any? { |field| arg.downcase.include?(field.downcase) }
            '[REDACTED]'
          else
            arg
          end
        else
          arg
        end
      end
    end

    def sanitize_hash(hash, sensitive_fields)
      hash.transform_values do |value|
        case value
        when Hash
          sanitize_hash(value, sensitive_fields)
        when Array
          value.map { |v| v.is_a?(Hash) ? sanitize_hash(v, sensitive_fields) : v }
        when String
          if sensitive_fields.any? { |field| value.downcase.include?(field.downcase) }
            '[REDACTED]'
          else
            value
          end
        else
          value
        end
      end
    end

    def sanitize_result(result)
      case result
      when Hash
        sanitize_hash(result, EzlogsRubyAgent.config.security.sanitize_fields)
      when String
        result.truncate(1000)
      else
        result
      end
    end

    def extract_retry_count
      # Extract retry count from job context
      if respond_to?(:retry_count)
        retry_count
      elsif respond_to?(:executions)
        executions - 1
      else
        0
      end
    rescue
      0
    end

    def extract_priority
      # Extract priority from job context
      if respond_to?(:priority)
        priority
      else
        'normal'
      end
    rescue
      'normal'
    end

    def extract_job_specific_metadata
      metadata = {}

      # Add ActiveJob specific metadata
      metadata[:active_job_id] = job_id if respond_to?(:job_id)

      metadata[:queue_name] = queue_name if respond_to?(:queue_name)

      metadata[:scheduled_at] = scheduled_at&.iso8601 if respond_to?(:scheduled_at)

      # Add Sidekiq specific metadata
      metadata[:sidekiq_jid] = jid if defined?(Sidekiq) && respond_to?(:jid)

      metadata
    end

    def job_name
      self.class.name
    end

    def job_id
      if respond_to?(:job_id)
        job_id
      elsif defined?(Sidekiq) && respond_to?(:jid)
        jid
      else
        "job_#{SecureRandom.urlsafe_base64(8)}"
      end
    rescue
      "job_#{SecureRandom.urlsafe_base64(8)}"
    end

    def queue_name
      if respond_to?(:queue_name)
        queue_name
      elsif respond_to?(:sidekiq_options) && sidekiq_options[:queue]
        sidekiq_options[:queue]
      else
        'default'
      end
    rescue
      'default'
    end

    def trackable_job?
      config = EzlogsRubyAgent.config
      job_name = self.class.name.downcase

      # Check if job matches any excluded patterns
      excluded = config.exclude_resources.any? do |pattern|
        job_name.match?(pattern)
      end
      return false if excluded

      # Check if job matches any included patterns
      if config.resources_to_track.any?
        included = config.resources_to_track.any? do |pattern|
          job_name.match?(pattern)
        end
        return false unless included
      end

      true
    end
  end
end
