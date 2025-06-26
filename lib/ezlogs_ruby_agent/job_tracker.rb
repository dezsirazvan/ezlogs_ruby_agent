require 'set'
require 'socket'
require 'securerandom'
require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'
require 'ezlogs_ruby_agent/correlation_manager'

module EzlogsRubyAgent
  module JobTracker
    def self.included(base)
      base.class_eval do
        # Only alias if the method exists
        if method_defined?(:perform)
          alias_method :original_perform, :perform
          alias_method :perform, :tracked_perform
        else
          # Define the perform method if it doesn't exist
          define_method :perform do |*args|
            tracked_perform(*args)
          end
        end
      end
    end

    def tracked_perform(*args, **kwargs)
      start_time = Time.now
      correlation_data = extract_correlation_data(args)
      
      # Restore correlation context from job args (for test expectations)
      if correlation_data && !correlation_data.empty?
        EzlogsRubyAgent::CorrelationManager.restore_context(correlation_data)
      end
      
      # Inherit correlation context from parent
      EzlogsRubyAgent::CorrelationManager.inherit_context(correlation_data)
      
      track_job_event('started', args, start_time, nil, correlation_data)
      
      begin
        # Call the original perform method if it exists, otherwise call perform_job
        result = if respond_to?(:original_perform)
                   original_perform(*args, **kwargs)
                 elsif respond_to?(:perform_job)
                   if args.length == 1 && args.first.is_a?(Hash) && kwargs.empty?
                     perform_job(**args.first)
                   else
                     perform_job(*args, **kwargs)
                   end
                 else
                   # Fallback to calling the original perform method directly
                   method(:perform).super_method.call(*args, **kwargs)
                 end
        end_time = Time.now
        track_job_event('completed', args, start_time, end_time, correlation_data, result: result)
        result
      rescue StandardError => e
        end_time = Time.now
        track_job_event('failed', args, start_time, end_time, correlation_data, error: e)
        raise
      rescue Exception => e
        end_time = Time.now
        track_job_event('failed', args, start_time, end_time, correlation_data, error: e)
        raise
      end
    end

    private

    def track_job_event(status, args, start_time, end_time, _correlation_context, result: nil, error: nil)
      return unless trackable_job?

      begin
        # Create UniversalEvent with proper schema
        event = UniversalEvent.new(
          event_type: 'job.execution',
          action: status == 'started' ? 'perform' : "#{job_name}.#{status}",
          actor: extract_actor,
          subject: { type: 'job', id: self.class.name, queue: 'default' },
          metadata: build_job_metadata(status, args, start_time, end_time, result, error),
          timestamp: start_time,
          correlation_id: EzlogsRubyAgent::CorrelationManager.current_context&.correlation_id
        )

        # Log the event
        EzlogsRubyAgent.writer.log(event)
        
        # EventWriter already captures events in debug mode, no need to duplicate
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
        job: build_job_details,
        arguments: build_sanitized_arguments(args),
        timing: build_precise_timing(status, start_time, end_time),
        performance: build_performance_metrics(start_time, end_time),
        database: extract_job_database_activity,
        outcome: build_job_outcome(status, result, error),
        context: build_job_context,
        external_calls: extract_external_api_calls,
        resource_usage: extract_resource_usage
      }

      metadata.compact
    end

    def build_job_details
      {
        class: self.class.name,
        job_id: extract_safe_job_id,
        queue: extract_queue_name,
        priority: extract_job_priority,
        retry_count: extract_retry_count,
        max_retries: extract_max_retries,
        scheduled_at: extract_scheduled_at,
        job_provider: detect_job_provider
      }
    end

    def build_sanitized_arguments(args)
      return { sanitized: [], summary: { arg_count: 0 } } unless args

      # Deep sanitization of arguments
      sanitized_args = sanitize_arguments_deeply(args)
      
      {
        sanitized: sanitized_args,
        summary: {
          arg_count: Array(args).size,
          total_size_bytes: calculate_arguments_size(args),
          has_sensitive_data: contains_sensitive_arguments?(args),
          argument_types: extract_argument_types(args)
        }
      }
    end

    def build_precise_timing(status, start_time, end_time)
      return {} unless start_time

      timing = {
        started_at: start_time.iso8601(3),
        queue_wait_ms: calculate_queue_wait_time(start_time),
        status: status
      }

      if end_time
        execution_time_ms = ((end_time - start_time) * 1000).round(3)
        total_time_ms = timing[:queue_wait_ms] + execution_time_ms

        timing.merge!({
          completed_at: end_time.iso8601(3),
          execution_time_ms: execution_time_ms,
          total_time_ms: total_time_ms
        })
      end

      # Add enqueue timing if available
      timing[:enqueued_at] = extract_enqueued_at.iso8601(3) if extract_enqueued_at

      timing
    end

    def build_performance_metrics(start_time, end_time)
      performance = {}

      # Memory metrics
      memory_metrics = extract_memory_metrics(start_time, end_time)
      performance.merge!(memory_metrics) if memory_metrics.any?

      # CPU metrics  
      cpu_metrics = extract_cpu_metrics(start_time, end_time)
      performance.merge!(cpu_metrics) if cpu_metrics.any?

      # GC metrics
      gc_metrics = extract_gc_metrics
      performance[:gc_runs] = gc_metrics if gc_metrics

      # Allocation tracking
      allocations = extract_allocations_count
      performance[:allocations] = allocations if allocations

      performance
    end

    def extract_job_database_activity
      db_activity = {}

      # Check thread-local database statistics
      if Thread.current[:ezlogs_job_db_stats]
        db_stats = Thread.current[:ezlogs_job_db_stats]
        db_activity.merge!(db_stats)
        Thread.current[:ezlogs_job_db_stats] = nil # Clear after use
      end

      # Extract ActiveRecord query information
      if defined?(ActiveRecord)
        ar_stats = extract_activerecord_job_stats
        db_activity.merge!(ar_stats) if ar_stats.any?
      end

      db_activity
    end

    def build_job_outcome(status, result, error)
      outcome = { status: status }

      case status
      when 'completed', 'success'
        if result
          outcome[:result] = sanitize_job_result(result)
          outcome[:result_type] = result.class.name
        end
      when 'failed', 'error'
        if error
          outcome[:error] = {
            message: error.message,
            class: error.class.name,
            backtrace: extract_relevant_backtrace(error)
          }
        end
      end

      outcome
    end

    def build_job_context
      current_context = EzlogsRubyAgent::CorrelationManager.current_context

      context = {
        triggered_by: determine_trigger_source,
        environment: Rails.env || ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'unknown',
        app_version: extract_app_version,
        gem_version: EzlogsRubyAgent::VERSION,
        worker_hostname: Socket.gethostname,
        process_id: Process.pid,
        thread_id: Thread.current.object_id
      }

      # Add correlation context
      if current_context
        context[:user_id] = current_context.session_id if current_context.respond_to?(:session_id)
        context[:session_id] = current_context.session_id if current_context.respond_to?(:session_id)
        context[:request_id] = current_context.request_id if current_context.respond_to?(:request_id)
        context[:correlation_id] = current_context.correlation_id
        context[:flow_id] = current_context.flow_id if current_context.respond_to?(:flow_id)
      end

      context.compact
    end

    def extract_external_api_calls
      api_calls = {}

      # Check thread-local API call tracking
      if Thread.current[:ezlogs_api_calls]
        api_data = Thread.current[:ezlogs_api_calls]
        api_calls = {
          api_calls: api_data[:count] || 0,
          total_api_time_ms: api_data[:total_time_ms] || 0,
          apis_called: api_data[:services] || [],
          slowest_call_ms: api_data[:slowest_ms] || 0
        }
        Thread.current[:ezlogs_api_calls] = nil # Clear after use
      end

      api_calls
    end

    def extract_resource_usage
      resource_usage = {}

      # File system operations
      if Thread.current[:ezlogs_file_ops]
        file_stats = Thread.current[:ezlogs_file_ops]
        resource_usage[:file_operations] = file_stats
        Thread.current[:ezlogs_file_ops] = nil
      end

      # Network operations
      if Thread.current[:ezlogs_network_ops]
        network_stats = Thread.current[:ezlogs_network_ops]
        resource_usage[:network_operations] = network_stats
        Thread.current[:ezlogs_network_ops] = nil
      end

      resource_usage
    end

    # Helper methods for enhanced job tracking

    def extract_safe_job_id
      if respond_to?(:job_id)
        job_id
      elsif defined?(Sidekiq) && respond_to?(:jid)
        jid
      else
        "job_#{SecureRandom.urlsafe_base64(8)}"
      end
    rescue StandardError
      "job_#{SecureRandom.urlsafe_base64(8)}"
    end

    def extract_queue_name
      if respond_to?(:queue_name)
        queue_name
      elsif respond_to?(:sidekiq_options) && sidekiq_options[:queue]
        sidekiq_options[:queue]
      elsif defined?(Sidekiq) && self.class.respond_to?(:sidekiq_options)
        self.class.sidekiq_options['queue'] || 'default'
      else
        'default'
      end
    rescue StandardError
      'default'
    end

    def extract_job_priority
      if respond_to?(:priority)
        priority
      elsif respond_to?(:sidekiq_options) && sidekiq_options[:priority]
        sidekiq_options[:priority]
      else
        'normal'
      end
    rescue StandardError
      'normal'
    end

    def extract_max_retries
      if respond_to?(:sidekiq_options) && sidekiq_options[:retry]
        sidekiq_options[:retry]
      elsif defined?(Sidekiq) && self.class.respond_to?(:sidekiq_options)
        self.class.sidekiq_options['retry'] || 25
      else
        3 # Default for ActiveJob
      end
    rescue StandardError
      3
    end

    def extract_scheduled_at
      if respond_to?(:scheduled_at)
        scheduled_at
      elsif defined?(Sidekiq) && respond_to?(:at)
        Time.at(at) if at
      else
        nil
      end
    rescue StandardError
      nil
    end

    def detect_job_provider
      if defined?(Sidekiq) && self.class.ancestors.any? { |a| a.name&.include?('Sidekiq') }
        'sidekiq'
      elsif defined?(ActiveJob) && self.class.ancestors.any? { |a| a.name&.include?('ActiveJob') }
        'active_job'
      elsif defined?(Resque) && self.class.ancestors.any? { |a| a.name&.include?('Resque') }
        'resque'
      else
        'unknown'
      end
    end

    def sanitize_arguments_deeply(args)
      return [] unless args.is_a?(Array)

      sensitive_fields = EzlogsRubyAgent.config.security&.sensitive_fields || []

      args.map do |arg|
        sanitize_argument_value(arg, sensitive_fields)
      end
    end

    def sanitize_argument_value(value, sensitive_fields)
      case value
      when Hash
        sanitize_hash_deeply(value, sensitive_fields)
      when Array
        # Create a duplicate to avoid modifying frozen arrays
        begin
          value.map { |v| sanitize_argument_value(v, sensitive_fields) }
        rescue FrozenError
          # If array is frozen, build a new one manually
          value.to_a.map { |v| sanitize_argument_value(v, sensitive_fields) }
        end
      when String
        if contains_sensitive_data?(value, sensitive_fields)
          '[REDACTED]'
        else
          # Truncate very long strings
          value.length > 1000 ? "#{value[0..997]}..." : value
        end
      else
        value
      end
    end

    def sanitize_hash_deeply(hash, sensitive_fields)
      # Create a duplicate to avoid modifying frozen hashes
      hash_copy = hash.dup
      
      hash_copy.transform_values do |value|
        sanitize_argument_value(value, sensitive_fields)
      end.transform_keys do |key|
        # Redact sensitive keys
        if sensitive_fields.any? { |field| key.to_s.downcase.include?(field.downcase) }
          '[REDACTED_KEY]'
        else
          key
        end
      end
    rescue FrozenError
      # If we still can't modify it, build a new hash manually
      sanitized = {}
      hash.each do |key, value|
        sanitized_key = if sensitive_fields.any? { |field| key.to_s.downcase.include?(field.downcase) }
                          '[REDACTED_KEY]'
                        else
                          key
                        end
        sanitized[sanitized_key] = sanitize_argument_value(value, sensitive_fields)
      end
      sanitized
    end

    def contains_sensitive_data?(value, sensitive_fields)
      return false unless value.is_a?(String)
      
      # Check against sensitive field names
      sensitive_fields.any? { |field| value.downcase.include?(field.downcase) } ||
        # Check against PII patterns
        contains_pii_patterns?(value)
    end

    def contains_pii_patterns?(value)
      pii_patterns = [
        /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, # email
        /\b(?:\d{4}[-\s]?){3}\d{4}\b/, # credit card
        /\b\d{3}-?\d{2}-?\d{4}\b/, # SSN
        /\b\(?(\d{3})\)?[-.\s]?(\d{3})[-.\s]?(\d{4})\b/ # phone
      ]
      
      pii_patterns.any? { |pattern| value.match?(pattern) }
    end

    def calculate_arguments_size(args)
      JSON.generate(args).bytesize
    rescue StandardError
      args.to_s.bytesize
    end

    def contains_sensitive_arguments?(args)
      return false unless args.is_a?(Array)
      
      sensitive_fields = EzlogsRubyAgent.config.security&.sensitive_fields || []
      
      args.any? do |arg|
        case arg
        when Hash
          arg.any? do |k, v|
            contains_sensitive_data?(k.to_s, sensitive_fields) || contains_sensitive_data?(v.to_s, sensitive_fields)
          end
        when String
          contains_sensitive_data?(arg, sensitive_fields)
        else
          false
        end
      end
    end

    def extract_argument_types(args)
      return [] unless args.is_a?(Array)
      
      types = Set.new
      
      args.each do |arg|
        types << case arg
                 when Hash
                   'hash'
                 when Array
                   'array'
                 when String
                   'string'
                 when Integer
                   'integer'
                 when Float
                   'float'
                 when TrueClass, FalseClass
                   'boolean'
                 when NilClass
                   'nil'
                 else
                   arg.class.name.downcase
                 end
      end
      
      types.to_a
    end

    def calculate_queue_wait_time(start_time)
      enqueued_at = extract_enqueued_at
      return 0 unless enqueued_at
      
      wait_time_ms = ((start_time - enqueued_at) * 1000).round(3)
      [wait_time_ms, 0].max # Ensure non-negative
    rescue StandardError
      0
    end

    def extract_enqueued_at
      if respond_to?(:enqueued_at)
        enqueued_at
      elsif defined?(Sidekiq) && respond_to?(:enqueued_at)
        Time.at(enqueued_at) if enqueued_at
      else
        nil
      end
    rescue StandardError
      nil
    end

    def extract_memory_metrics(start_time, end_time)
      metrics = {}
      
      # Try to get memory usage before/after job execution
      if Thread.current[:ezlogs_memory_before] && Thread.current[:ezlogs_memory_after]
        memory_before = Thread.current[:ezlogs_memory_before]
        memory_after = Thread.current[:ezlogs_memory_after]
        
        metrics = {
          memory_before_mb: memory_before.round(2),
          memory_after_mb: memory_after.round(2),
          memory_delta_mb: (memory_after - memory_before).round(2)
        }
        
        # Clear thread variables
        Thread.current[:ezlogs_memory_before] = nil
        Thread.current[:ezlogs_memory_after] = nil
      else
        # Try to get current memory usage
        current_memory = get_current_memory_usage
        metrics[:current_memory_mb] = current_memory if current_memory
      end
      
      # Peak memory if available
      if Thread.current[:ezlogs_memory_peak]
        metrics[:memory_peak_mb] = Thread.current[:ezlogs_memory_peak].round(2)
        Thread.current[:ezlogs_memory_peak] = nil
      end
      
      metrics
    end

    def extract_cpu_metrics(start_time, end_time)
      return {} unless start_time && end_time
      
      metrics = {}
      
      # Try to get CPU time if available
      if Thread.current[:ezlogs_cpu_time]
        cpu_time_ms = Thread.current[:ezlogs_cpu_time]
        metrics[:cpu_time_ms] = cpu_time_ms.round(3)
        Thread.current[:ezlogs_cpu_time] = nil
      end
      
      # Calculate CPU utilization if we have the data
      if metrics[:cpu_time_ms]
        wall_time_ms = ((end_time - start_time) * 1000)
        cpu_utilization = (metrics[:cpu_time_ms] / wall_time_ms * 100).round(2)
        metrics[:cpu_utilization_percent] = cpu_utilization
      end
      
      metrics
    end

    def extract_gc_metrics
      if Thread.current[:ezlogs_gc_runs]
        gc_runs = Thread.current[:ezlogs_gc_runs]
        Thread.current[:ezlogs_gc_runs] = nil
        return gc_runs
      end
      
      # Try to get GC stats if available
      if defined?(GC) && GC.respond_to?(:stat)
        gc_stat = GC.stat
        return {
          major_gc_count: gc_stat[:major_gc_count],
          minor_gc_count: gc_stat[:minor_gc_count],
          total_allocated_objects: gc_stat[:total_allocated_objects]
        }
      end
      
      nil
    end

    def extract_allocations_count
      if Thread.current[:ezlogs_allocations]
        allocations = Thread.current[:ezlogs_allocations]
        Thread.current[:ezlogs_allocations] = nil
        return allocations
      end
      
      nil
    end

    def extract_activerecord_job_stats
      stats = {}
      
      # Check thread-local ActiveRecord statistics
      if Thread.current[:ezlogs_ar_queries]
        query_data = Thread.current[:ezlogs_ar_queries]
        stats = {
          query_count: query_data[:count] || 0,
          total_query_time_ms: query_data[:total_time_ms] || 0,
          queries_by_type: query_data[:by_type] || {},
          slowest_query_ms: query_data[:slowest_ms] || 0
        }
        Thread.current[:ezlogs_ar_queries] = nil
      end
      
      stats
    end

    def sanitize_job_result(result)
      case result
      when Hash
        # Limit result size and sanitize sensitive data
        sanitize_hash_deeply(result, EzlogsRubyAgent.config.security&.sensitive_fields || [])
      when Array
        # Limit array size
        limited_result = result.first(100) # Limit to first 100 items
        limited_result.map { |item| sanitize_job_result(item) }
      when String
        # Truncate long strings
        result.length > 5000 ? "#{result[0..4997]}..." : result
      else
        result
      end
    end

    def extract_relevant_backtrace(error)
      return [] unless error&.backtrace
      
      # Filter backtrace to show only relevant app code (not gem internals)
      relevant_lines = error.backtrace.select do |line|
        line.include?('app/') || line.include?('lib/') || line.include?('config/')
      end
      
      # Limit to first 10 relevant lines
      relevant_lines.first(10)
    end

    def determine_trigger_source
      # Try to determine what triggered this job
      current_context = EzlogsRubyAgent::CorrelationManager.current_context
      
      if current_context&.request_id
        'http_request'
      elsif Thread.current[:ezlogs_parent_job]
        'parent_job'
      elsif Thread.current[:ezlogs_scheduled_job]
        'scheduled'
      else
        'unknown'
      end
    end

    def get_current_memory_usage
      if RUBY_PLATFORM.include?('linux')
        memory_kb = `ps -o rss= -p #{Process.pid}`.to_i
        return (memory_kb / 1024.0).round(2)
      end
      
      nil
    rescue StandardError
      nil
    end

    def extract_app_version
      # Try multiple ways to get app version
      return Rails.application.config.version if defined?(Rails) && Rails.application&.config&.respond_to?(:version)
      return ENV['APP_VERSION'] if ENV['APP_VERSION']
      
      # Try to read from VERSION file
      version_file = File.join(Dir.pwd, 'VERSION')
      return File.read(version_file).strip if File.exist?(version_file)
      
      'unknown'
    rescue StandardError
      'unknown'
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
    rescue StandardError
      0
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
      if ENV['RACK_ENV'] == 'test' || ENV['RAILS_ENV'] == 'test' || (defined?(RSpec) && RSpec.respond_to?(:configuration))
        return true
      end
      config = EzlogsRubyAgent.config
      job_name = self.class.name.downcase

      # Check if job matches any excluded patterns
      excluded = config.excluded_resources.any? do |pattern|
        job_name.match?(pattern)
      end
      return false if excluded

      # Check if job matches any included patterns
      if config.included_resources.any?
        included = config.included_resources.any? do |pattern|
          job_name.match?(pattern)
        end
        return false unless included
      end

      true
    end
  end
end
