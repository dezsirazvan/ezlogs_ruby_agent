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
                :correlation_id, :correlation, :metadata, :platform, :validation_errors

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
    #
    # @raise [ArgumentError] If required keywords are missing
    # @raise [InvalidEventError] If validation fails
    def initialize(event_type:, action:, actor:, subject: nil, metadata: nil,
                   timestamp: nil, correlation_id: nil, event_id: nil)
      @event_type = event_type
      @action = action
      @actor = deep_freeze(actor.dup)
      @subject = subject ? deep_freeze(subject.dup) : nil
      @metadata = metadata ? deep_freeze(metadata.dup) : {}.freeze
      @timestamp = timestamp || Time.now.utc
      @event_id = event_id || generate_event_id
      @correlation_id = correlation_id || extract_correlation_id
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
      return context[:correlation_id] if context&.key?(:correlation_id)

      # Fallback to legacy thread variable
      return Thread.current[:correlation_id] if Thread.current[:correlation_id]

      # Generate new correlation ID
      "flow_#{SecureRandom.urlsafe_base64(16).tr('_-', 'cd')}"
    end

    # Build correlation context with request/session information
    def build_correlation_context
      context = Thread.current[:ezlogs_context] || {}

      @correlation = {
        correlation_id: @correlation_id,
        flow_id: context[:flow_id],
        session_id: context[:session_id],
        request_id: context[:request_id],
        parent_event_id: context[:parent_event_id]
      }.compact.freeze
    end

    # Build platform context with service and environment information
    def build_platform_context
      config = EzlogsRubyAgent.config

      @platform = {
        service: config.service_name || 'ruby-app',
        environment: config.environment || Rails.env || ENV['RACK_ENV'] || 'development',
        agent_version: EzlogsRubyAgent::VERSION,
        ruby_version: RUBY_VERSION,
        hostname: Socket.gethostname
      }.freeze
    rescue StandardError
      # Fallback if any platform detection fails
      @platform = {
        service: 'ruby-app',
        environment: 'unknown',
        agent_version: EzlogsRubyAgent::VERSION,
        ruby_version: RUBY_VERSION
      }.freeze
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
