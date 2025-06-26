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

    attr_reader :event_id, :timestamp, :event_type, :action, :actor, :subject,
                :correlation_id, :correlation, :metadata, :platform, :validation_errors,
                :correlation_context, :payload

    # Create a new UniversalEvent with validation and automatic field generation
    #
    # @param event_type [String] The type of event (e.g., 'user.action', 'http.request')
    # @param action [String] The specific action taken (e.g., 'login', 'GET', 'create')
    # @param actor [Hash] Who performed the action with :type and :id keys
    # @param subject [Hash, nil] What was acted upon (optional)
    # @param metadata [Hash, nil] Additional event-specific data (optional)
    # @param timestamp [Time, nil] When the event occurred (defaults to now)
    # @param correlation_id [String, nil] Correlation ID (auto-generated if not provided)
    # @param event_id [String, nil] Unique event ID (auto-generated if not provided)
    # @param correlation_context [Hash, nil] Correlation context (optional)
    # @param payload [Hash, nil] Payload data (optional)
    #
    # @raise [ArgumentError] If required keywords are missing
    # @raise [InvalidEventError] If validation fails
    def initialize(event_type:, action:, actor:, subject: nil, metadata: nil,
                   timestamp: nil, correlation_id: nil, event_id: nil,
                   correlation_context: nil, payload: nil)
      @event_type = event_type
      @action = action
      @actor = deep_freeze(actor.dup)
      @subject = subject ? deep_freeze(subject.dup) : nil
      @metadata = metadata ? deep_freeze(metadata.dup) : {}.freeze
      @timestamp = timestamp || Time.now.utc
      @event_id = event_id || generate_event_id
      @correlation_id = correlation_id || extract_correlation_id
      @correlation_context = correlation_context
      @payload = payload ? deep_freeze(payload.dup) : nil
      @validation_errors = []

      validate!
      build_correlation_context
      build_platform_context
      freeze_self
    end

    # Convert event to hash representation for serialization
    #
    # @return [Hash] Complete event data as hash
    def to_h
      {
        event_id: @event_id,
        timestamp: @timestamp,
        event_type: @event_type,
        action: @action,
        actor: @actor,
        subject: @subject,
        correlation: @correlation,
        correlation_context: @correlation_context,
        payload: @payload,
        metadata: @metadata,
        platform: @platform
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

    # Extract correlation ID from thread context or generate new one
    def extract_correlation_id
      context = Thread.current[:ezlogs_context]
      if context.respond_to?(:correlation_id)
        return context.correlation_id
      elsif context.is_a?(Hash) && context.key?(:correlation_id)
        return context[:correlation_id]
      end

      # Fallback to legacy thread variable
      return Thread.current[:correlation_id] if Thread.current[:correlation_id]

      # Generate new correlation ID
      "flow_#{SecureRandom.urlsafe_base64(16).tr('_-', 'cd')}"
    end

    # Build correlation context with request/session information
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

      @correlation = {
        correlation_id: @correlation_id,
        flow_id: context_hash[:flow_id],
        session_id: context_hash[:session_id],
        request_id: context_hash[:request_id],
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
        source: build_detailed_source_info
      }.freeze
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
      EzlogsRubyAgent.config&.environment || 'unknown-environment'
    end

    def hostname
      Socket.gethostname
    rescue StandardError
      'unknown-hostname'
    end

    def determine_collector_type
      # Analyze the call stack to determine which collector created this event
      caller_lines = caller(1, 10)

      return 'http_tracker' if caller_lines.any? { |line| line.include?('http_tracker.rb') }
      return 'callbacks_tracker' if caller_lines.any? { |line| line.include?('callbacks_tracker.rb') }
      return 'job_tracker' if caller_lines.any? { |line| line.include?('job_tracker.rb') }
      return 'sidekiq_tracker' if caller_lines.any? { |line| line.include?('sidekiq_job_tracker.rb') }
      return 'manual_logging' if caller_lines.any? { |line| line.include?('log_event') }

      'unknown_collector'
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
      when 'manual_logging'
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
