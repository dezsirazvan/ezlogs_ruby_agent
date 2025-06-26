require 'securerandom'
require 'time'
require 'socket'

module EzlogsRubyAgent
  # Custom exception for invalid events
  class InvalidEventError < StandardError; end

  # UniversalEvent provides a consistent, immutable event structure for all
  # event types in the EzlogsRubyAgent system. Every event, whether HTTP request,
  # database change, or background job, uses this same beautiful schema.
  #
  # @example Creating a user action event
  #   event = UniversalEvent.new(
  #     event_type: 'user.action',
  #     action: 'profile.updated',
  #     actor: { type: 'user', id: '123', email: 'user@example.com' },
  #     subject: { type: 'profile', id: '456' },
  #     metadata: { field: 'email', old_value: 'old@test.com', new_value: 'new@test.com' }
  #   )
  #
  # @example Creating an HTTP request event
  #   event = UniversalEvent.new(
  #     event_type: 'http.request',
  #     action: 'GET',
  #     actor: { type: 'user', id: '123' },
  #     subject: { type: 'endpoint', id: '/api/users' },
  #     metadata: { status: 200, duration: 0.150 }
  #   )
  class UniversalEvent
    # Event type must follow namespace.category pattern
    EVENT_TYPE_PATTERN = /\A[a-z][a-z0-9]*\.[a-z][a-z0-9_]*\z/

    attr_reader :event_id, :event_type, :action, :actor, :subject,
                :correlation_id, :correlation, :metadata, :platform, :validation_errors,
                :correlation_context, :payload, :timing

    # Create a new UniversalEvent with validation and automatic field generation
    #
    # @param event_type [String] The type of event (e.g., 'user.action', 'http.request')
    # @param action [String] The specific action taken (e.g., 'login', 'GET', 'create')
    # @param actor [Hash] Who performed the action with :type and :id keys
    # @param subject [Hash, nil] What was acted upon (optional)
    # @param metadata [Hash, nil] Additional event-specific data (optional)
    # @param timing [Hash, nil] Timing data (optional, will be enhanced automatically)
    # @param correlation_id [String, nil] Correlation ID (auto-generated if not provided)
    # @param event_id [String, nil] Unique event ID (auto-generated if not provided)
    # @param correlation_context [Hash, nil] Correlation context (optional)
    # @param payload [Hash, nil] Payload data (optional)
    # @param timing [Hash, nil] Timing data (optional, will be enhanced automatically)
    #
    # @raise [ArgumentError] If required keywords are missing
    # @raise [InvalidEventError] If validation fails
    def initialize(event_type:, action:, actor:, subject: nil, metadata: nil,
                   correlation_id: nil, event_id: nil,
                   correlation_context: nil, payload: nil, timing: nil)
      @event_type = event_type
      @action = action
      @actor = deep_freeze(actor.frozen? ? safe_dup_hash(actor) : actor.dup)
      @subject = if subject
                   safe_subject = subject.frozen? ? safe_dup_hash(subject) : subject.dup
                   deep_freeze(safe_subject)
                 else
                   nil
                 end
      @metadata = if metadata
                    safe_metadata = metadata.frozen? ? safe_dup_hash(metadata) : metadata.dup
                    deep_freeze(safe_metadata)
                  else
                    {}.freeze
                  end
      @event_created_at = Time.now.utc
      @event_id = event_id || generate_event_id
      @correlation_id = correlation_id || extract_correlation_id
      @correlation_context = correlation_context
      @payload = if payload
                   safe_payload = payload.frozen? ? safe_dup_hash(payload) : payload.dup
                   deep_freeze(safe_payload)
                 else
                   nil
                 end
      @validation_errors = []

      # ✅ CRITICAL FIX: Enhanced timing for ALL events
      @timing = build_comprehensive_timing(timing)

      validate!
      build_correlation_context
      build_platform_context
      build_environment_context
      build_impact_classification
      freeze_self
    end

    # Convert event to hash representation for serialization
    #
    # @return [Hash] Complete event data as hash
    def to_h
      {
        event_id: @event_id,
        event_type: @event_type,
        action: @action,
        actor: @actor,
        subject: @subject,
        correlation: @correlation,
        correlation_context: @correlation_context,
        payload: @payload,
        metadata: @metadata,
        timing: @timing,
        platform: @platform,
        environment: @environment,
        impact: @impact
      }.compact
    end

    # Check if event passes all validations
    #
    # @return [Boolean] true if event is valid
    def valid?
      @validation_errors ||= []
      @validation_errors.empty?
    end

    private

    # ✅ CRITICAL FIX: Comprehensive timing for ALL events
    def build_comprehensive_timing(provided_timing = nil)
      event_creation_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      timing = {
        event_created_at: @event_created_at.iso8601(3),
        event_creation_time_ms: 0.0 # Will be calculated at end
      }

      # Merge provided timing data
      timing.merge!(provided_timing) if provided_timing.is_a?(Hash)

      # Extract comprehensive timing from thread context
      if Thread.current[:ezlogs_timing_context]
        timing_context = Thread.current[:ezlogs_timing_context]
        timing.merge!(extract_timing_from_context(timing_context))
      end

      # Add operation-specific timing based on event type
      case @event_type
      when 'http.request'
        timing.merge!(extract_http_timing)
      when 'data.change'
        timing.merge!(extract_data_change_timing)
      when 'job.execution', 'sidekiq.job'
        timing.merge!(extract_job_timing)
      end

      # Calculate event creation overhead
      event_creation_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      timing[:event_creation_time_ms] = ((event_creation_end - event_creation_start) * 1000).round(6)

      deep_freeze(timing)
    end

    def extract_timing_from_context(timing_context)
      context_timing = {}

      # Standard timing fields that should be present
      if timing_context[:started_at] && timing_context[:completed_at]
        start_time = timing_context[:started_at]
        end_time = timing_context[:completed_at]

        context_timing.merge!({
          started_at: start_time.iso8601(3),
          completed_at: end_time.iso8601(3),
          total_duration_ms: ((end_time - start_time) * 1000).round(3)
        })
      end

      # Extract performance metrics
      if timing_context[:memory_before_mb] && timing_context[:memory_after_mb]
        context_timing[:memory_allocated_mb] =
          (timing_context[:memory_after_mb] - timing_context[:memory_before_mb]).round(3)
        context_timing[:memory_peak_mb] = timing_context[:memory_peak_mb] if timing_context[:memory_peak_mb]
      end

      # Extract CPU and GC metrics
      context_timing[:cpu_time_ms] = timing_context[:cpu_time_ms] if timing_context[:cpu_time_ms]
      context_timing[:gc_count] = timing_context[:gc_count] if timing_context[:gc_count]
      context_timing[:allocations] = timing_context[:allocations] if timing_context[:allocations]

      context_timing
    end

    def extract_http_timing
      http_timing = {}

      # Queue time (time between request received and processing started)
      if Thread.current[:ezlogs_request_received_at] && Thread.current[:ezlogs_request_start]
        queue_time = Thread.current[:ezlogs_request_start] - Thread.current[:ezlogs_request_received_at]
        http_timing[:queue_time_ms] = (queue_time * 1000).round(3)
      end

      # Middleware timing
      if Thread.current[:ezlogs_middleware_duration]
        http_timing[:middleware_time_ms] = Thread.current[:ezlogs_middleware_duration].round(3)
      end

      # Controller timing
      if Thread.current[:ezlogs_controller_duration]
        http_timing[:controller_time_ms] = Thread.current[:ezlogs_controller_duration].round(3)
      end

      # View rendering timing
      if Thread.current[:ezlogs_view_duration]
        http_timing[:view_time_ms] = Thread.current[:ezlogs_view_duration].round(3)
      end

      # Database timing
      http_timing[:db_time_ms] = Thread.current[:ezlogs_db_duration].round(3) if Thread.current[:ezlogs_db_duration]

      # Cache timing
      if Thread.current[:ezlogs_cache_duration]
        http_timing[:cache_time_ms] = Thread.current[:ezlogs_cache_duration].round(3)
      end

      # External API timing
      if Thread.current[:ezlogs_external_api_duration]
        http_timing[:external_api_time_ms] = Thread.current[:ezlogs_external_api_duration].round(3)
      end

      http_timing
    end

    def extract_data_change_timing
      data_timing = {}

      # Validation timing
      if Thread.current[:ezlogs_validation_duration]
        data_timing[:validation_time_ms] = Thread.current[:ezlogs_validation_duration].round(3)
      end

      # Callback timing
      if Thread.current[:ezlogs_callback_duration]
        data_timing[:callback_time_ms] = Thread.current[:ezlogs_callback_duration].round(3)
      end

      # Database operation timing
      if Thread.current[:ezlogs_db_operation_duration]
        data_timing[:database_time_ms] = Thread.current[:ezlogs_db_operation_duration].round(3)
      end

      # Index update timing
      if Thread.current[:ezlogs_index_update_duration]
        data_timing[:index_update_time_ms] = Thread.current[:ezlogs_index_update_duration].round(3)
      end

      data_timing
    end

    def extract_job_timing
      job_timing = {}

      # Queue wait time (time between enqueue and execution start)
      if Thread.current[:ezlogs_job_enqueued_at] && Thread.current[:ezlogs_job_started_at]
        wait_time = Thread.current[:ezlogs_job_started_at] - Thread.current[:ezlogs_job_enqueued_at]
        job_timing[:queue_wait_time_ms] = (wait_time * 1000).round(3)
      end

      # Setup time (job initialization)
      if Thread.current[:ezlogs_job_setup_duration]
        job_timing[:setup_time_ms] = Thread.current[:ezlogs_job_setup_duration].round(3)
      end

      # Cleanup time
      if Thread.current[:ezlogs_job_cleanup_duration]
        job_timing[:cleanup_time_ms] = Thread.current[:ezlogs_job_cleanup_duration].round(3)
      end

      # Retry delay (if this was a retry)
      if Thread.current[:ezlogs_job_retry_delay]
        job_timing[:retry_delay_ms] = Thread.current[:ezlogs_job_retry_delay].round(3)
      end

      job_timing
    end

    # Validate all aspects of the event
    def validate!
      validate_event_type
      validate_action
      validate_actor
      validate_subject if @subject
      validate_metadata if @metadata && !@metadata.empty?

      return if @validation_errors.empty?

      raise InvalidEventError, "Event validation failed: #{@validation_errors.join(', ')}"
    end

    def validate_event_type
      return if @event_type.is_a?(String) && @event_type.match?(EVENT_TYPE_PATTERN)

      @validation_errors << "event_type must match pattern 'namespace.category' (e.g., 'user.action')"
    end

    def validate_action
      return if @action.is_a?(String) && !@action.empty?

      @validation_errors << 'action must be a non-empty string'
    end

    def validate_actor
      unless @actor.is_a?(Hash)
        @validation_errors << 'actor must be a hash'
        return
      end

      @validation_errors << 'actor must have type' unless @actor.key?(:type) || @actor.key?('type')
      @validation_errors << 'actor must have id' unless @actor.key?(:id) || @actor.key?('id')
    end

    def validate_subject
      unless @subject.is_a?(Hash)
        @validation_errors << 'subject must be a hash when provided'
        return
      end

      @validation_errors << 'subject must have type' unless @subject.key?(:type) || @subject.key?('type')
    end

    def validate_metadata
      return if @metadata.is_a?(Hash)

      @validation_errors << 'metadata must be a hash when provided'
    end

    # Generate a unique event ID with readable prefix
    def generate_event_id
      "evt_#{SecureRandom.urlsafe_base64(16).tr('_-', 'ab')}"
    end

    # ✅ CRITICAL FIX: Extract correlation ID with flow_id priority
    def extract_correlation_id
      context = Thread.current[:ezlogs_context]

      # Priority 1: Use flow_id for correlation (CRITICAL FIX)
      if context.respond_to?(:flow_id) && context.flow_id
        return context.flow_id
      elsif context.is_a?(Hash) && context[:flow_id]
        return context[:flow_id]
      end

      # Priority 2: Use existing correlation_id
      if context.respond_to?(:correlation_id)
        return context.correlation_id
      elsif context.is_a?(Hash) && context.key?(:correlation_id)
        return context[:correlation_id]
      end

      # Priority 3: Fallback to legacy thread variable
      return Thread.current[:correlation_id] if Thread.current[:correlation_id]

      # Priority 4: Generate new flow-based correlation ID
      "flow_#{SecureRandom.urlsafe_base64(16).tr('_-', 'cd')}"
    end

    # ✅ CRITICAL FIX: Build correlation context with proper flow_id usage
    def build_correlation_context
      context = Thread.current[:ezlogs_context]
      context_hash =
        if context.is_a?(Hash)
          context
        elsif context.respond_to?(:to_h)
          context.to_h
        else
          {}
        end

      # Use flow_id as the primary correlation identifier
      flow_id = context_hash[:flow_id] || @correlation_id

      @correlation = {
        correlation_id: @correlation_id,
        flow_id: flow_id,
        session_id: context_hash[:session_id],
        request_id: context_hash[:request_id],
        transaction_id: context_hash[:transaction_id],
        trace_id: context_hash[:trace_id],
        parent_event_id: context_hash[:parent_event_id]
      }.compact.freeze
    end

    # Build platform context with detailed source information
    def build_platform_context
      @platform = {
        service: service_name,
        environment: environment_name,
        agent_version: EzlogsRubyAgent::VERSION,
        ruby_version: RUBY_VERSION,
        hostname: hostname,
        process_id: Process.pid,
        thread_id: Thread.current.object_id.to_s,
        source: build_detailed_source_info
      }.freeze
    end

    # ✅ NEW: Build environment context for better debugging
    def build_environment_context
      @environment = {
        hostname: hostname,
        process_id: Process.pid,
        thread_id: Thread.current.object_id.to_s,
        rails_env: extract_rails_env,
        app_version: extract_app_version,
        gem_version: EzlogsRubyAgent::VERSION,
        ruby_engine: defined?(RUBY_ENGINE) ? RUBY_ENGINE : 'ruby',
        ruby_platform: RUBY_PLATFORM
      }.compact.freeze
    end

    # ✅ NEW: Build impact classification for business intelligence
    def build_impact_classification
      @impact = {
        performance_tier: classify_performance_tier,
        data_sensitivity: classify_data_sensitivity,
        business_criticality: classify_business_criticality,
        user_facing: determine_user_facing,
        billable_operation: determine_billable_operation
      }.compact.freeze
    end

    def classify_performance_tier
      # Classify based on timing if available
      total_duration = @timing[:total_duration_ms] || @timing[:execution_time_ms]
      return 'unknown' unless total_duration

      case total_duration
      when 0..10 then 'fast'
      when 10..100 then 'normal'
      when 100..1000 then 'slow'
      else 'critical'
      end
    end

    def classify_data_sensitivity
      case @event_type
      when 'user.action', 'data.change'
        # Check for sensitive fields in metadata
        if @metadata.to_s.match?(/password|ssn|credit_card|email|phone/i)
          'restricted'
        else
          'internal'
        end
      when 'http.request'
        'public'
      else
        'internal'
      end
    end

    def classify_business_criticality
      case @event_type
      when 'http.request'
        # Check status codes in metadata
        status = @metadata.dig(:response, :status) || @metadata[:status]
        return 'critical' if status && status >= 500
        return 'high' if status && status >= 400

        'medium'
      when 'data.change'
        # Data changes are generally high criticality
        'high'
      when 'job.execution'
        # Jobs are medium unless they fail
        status = @metadata.dig(:outcome, :status) || @metadata[:status]
        return 'critical' if status == 'failed'

        'medium'
      else
        'low'
      end
    end

    def determine_user_facing
      case @event_type
      when 'http.request' then true
      when 'data.change'
        # Check if this affects user-visible data
        @metadata.to_s.match?(/profile|user|account|public/i)
      else
        false
      end
    end

    def determine_billable_operation
      # Determine if this operation should be counted for billing
      case @event_type
      when 'http.request'
        # API calls are typically billable
        @action.match?(/^(GET|POST|PUT|DELETE|PATCH)/i)
      when 'data.change'
        # Data modifications might be billable
        @action.match? / (create | update | delete) / i
      else
        false
      end
    end

    # Build detailed source information for precise event attribution
    def build_detailed_source_info
      {
        gem: 'ezlogs_ruby_agent',
        version: EzlogsRubyAgent::VERSION,
        collector: determine_collector_type,
        location: extract_precise_location,
        trigger: extract_trigger_information
      }
    end

    def service_name
      EzlogsRubyAgent.config&.service_name || 'unknown-service'
    end

    def environment_name
      EzlogsRubyAgent.config&.environment || extract_rails_env || 'unknown-environment'
    end

    def extract_rails_env
      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env
      elsif ENV['RAILS_ENV']
        ENV['RAILS_ENV']
      elsif ENV['RACK_ENV']
        ENV['RACK_ENV']
      else
        nil
      end
    end

    def extract_app_version
      # Try multiple ways to get app version
      return Rails.application.config.version if defined?(Rails) && Rails.application&.config&.respond_to?(:version)
      return ENV['APP_VERSION'] if ENV['APP_VERSION']
      return File.read('VERSION').strip if File.exist?('VERSION')

      nil
    rescue StandardError
      nil
    end

    def hostname
      Socket.gethostname
    rescue StandardError
      'unknown-hostname'
    end

    def determine_collector_type
      # Analyze the call stack to determine which collector created this event
      caller_lines = caller(1, 10)

      return 'http_tracker' if caller_lines.any? { |line| line.include?('http_tracker') }
      return 'job_tracker' if caller_lines.any? { |line| line.include?('job_tracker') }
      return 'callbacks_tracker' if caller_lines.any? { |line| line.include?('callbacks_tracker') }
      return 'sidekiq_tracker' if caller_lines.any? { |line| line.include?('sidekiq') }

      'manual'
    end

    def extract_precise_location
      # Find the first call stack entry that's in the application code
      caller_lines = caller(1, 20)

      app_caller = caller_lines.find do |line|
        line.include?('app/') &&
          !line.include?('ezlogs') &&
          !line.include?('vendor/') &&
          !line.include?('gems/')
      end

      return parse_caller_location(app_caller) if app_caller

      # Fallback to the first non-gem caller
      non_gem_caller = caller_lines.find do |line|
        !line.include?('gems/') &&
          !line.include?('vendor/') &&
          !line.include?('ezlogs')
      end

      return parse_caller_location(non_gem_caller) if non_gem_caller

      # Last resort: just take the immediate caller
      parse_caller_location(caller_lines.first)
    end

    def parse_caller_location(caller_line)
      return {} unless caller_line

      # Parse caller format: /path/file.rb:line:in `method'
      if caller_line.match(%r{([^/]+\.rb):(\d+):in `([^']+)'})
        file_name = ::Regexp.last_match(1)
        line_number = ::Regexp.last_match(2).to_i
        method_name = ::Regexp.last_match(3)

        {
          file: file_name,
          line: line_number,
          method: method_name,
          full_path: extract_full_path_from_caller(caller_line)
        }
      else
        { raw_caller: caller_line }
      end
    end

    def extract_full_path_from_caller(caller_line)
      # Extract the full file path from the caller string
      if caller_line.match(/^([^:]+):/)
        full_path = ::Regexp.last_match(1)

        # Try to make it relative to the project root
        project_root = find_project_root
        if project_root && full_path.start_with?(project_root)
          return full_path[project_root.length + 1..-1] # +1 to remove leading slash
        end

        full_path
      else
        nil
      end
    end

    def extract_trigger_information
      trigger_info = {}

      # Determine the type of trigger based on the collector
      case determine_collector_type
      when 'http_tracker'
        trigger_info[:type] = 'http_request'
        trigger_info[:source] = 'rack_middleware'
      when 'callbacks_tracker'
        trigger_info.merge!(extract_activerecord_trigger_info)
      when 'job_tracker', 'sidekiq_tracker'
        trigger_info[:type] = 'background_job'
        trigger_info[:source] = 'job_middleware'
      when 'manual'
        trigger_info[:type] = 'manual'
        trigger_info[:source] = 'application_code'
      end

      trigger_info
    end

    def extract_activerecord_trigger_info
      # Try to determine which ActiveRecord callback triggered this
      caller_lines = caller(1, 15)

      callback_caller = caller_lines.find { |line| line.include?('log_') && line.include?('_event') }

      if callback_caller && callback_caller.match(/log_(\w+)_event/)
        callback_type = ::Regexp.last_match(1)
        return {
          type: 'activerecord_callback',
          hook: "after_#{callback_type}",
          source: 'activerecord_observer'
        }
      end

      {
        type: 'activerecord_callback',
        hook: 'unknown',
        source: 'activerecord_observer'
      }
    end

    def find_project_root
      # Try to find the project root directory
      current_dir = Dir.pwd

      # Look for common project root indicators
      root_indicators = %w[Gemfile Rakefile .git config.ru]

      while current_dir != '/' && current_dir != current_dir.dirname
        return current_dir if root_indicators.any? { |indicator| File.exist?(File.join(current_dir, indicator)) }

        current_dir = File.dirname(current_dir)
      end

      Dir.pwd # Fallback to current directory
    end

    # Safely duplicate a hash that might be frozen
    def safe_dup_hash(hash)
      return {} unless hash.is_a?(Hash)

      unfrozen = {}
      hash.each do |key, value|
        new_key = key.respond_to?(:dup) && !key.is_a?(Symbol) ? key.dup : key
        new_value = case value
                    when Hash
                      safe_dup_hash(value)
                    when Array
                      value.map { |item| item.is_a?(Hash) ? safe_dup_hash(item) : item }
                    else
                      value.respond_to?(:dup) && !value.is_a?(Symbol) && !value.is_a?(Numeric) && !value.nil? ? value.dup : value
                    end
        unfrozen[new_key] = new_value
      rescue StandardError
        # If we can't duplicate, just use the original value
        unfrozen[key] = value
      end
      unfrozen
    rescue StandardError
      {}
    end

    # Recursively freeze nested hashes and arrays
    def deep_freeze(obj)
      case obj
      when Hash
        obj.each_value { |v| deep_freeze(v) }
        obj.freeze
      when Array
        obj.each { |v| deep_freeze(v) }
        obj.freeze
      else
        obj.freeze if obj.respond_to?(:freeze)
      end
      obj
    end

    # Make the event instance immutable
    def freeze_self
      instance_variables.each do |var|
        instance_variable_get(var).freeze
      end
      freeze
    end
  end
end
