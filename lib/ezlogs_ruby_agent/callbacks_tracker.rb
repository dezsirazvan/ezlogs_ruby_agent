require 'active_support/concern'
require 'securerandom'
require 'socket'
require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'
require 'ezlogs_ruby_agent/correlation_manager'

module EzlogsRubyAgent
  module CallbacksTracker
    extend ActiveSupport::Concern

    included do
      after_create :log_create_event, if: :trackable_resource?
      after_update :log_update_event, if: :trackable_resource?
      after_destroy :log_destroy_event, if: :trackable_resource?
    end

    private

    def trackable_resource?
      config = EzlogsRubyAgent.config
      resource_name = self.class.name

      resource_inclusion = config.included_resources.empty? ||
                           config.included_resources.any? { |resource| resource.match?(resource_name) }
      resource_exclusion = config.excluded_resources.any? { |resource| resource.match?(resource_name) }

      resource_inclusion && !resource_exclusion
    end

    def log_create_event
      log_event("create", attributes, nil)
    end

    def log_update_event
      # Use saved_changes instead of previous_changes for Rails 5.2+
      changes = respond_to?(:saved_changes) ? saved_changes : previous_changes
      # Use saved_attributes instead of attributes_before_last_save
      previous_attrs = respond_to?(:saved_attributes) ? saved_attributes : attributes_was
      log_event("update", changes, previous_attrs)
    end

    def log_destroy_event
      log_event("destroy", attributes, nil)
    end

    def log_event(action, changes, previous_attributes = nil)
      # Create UniversalEvent with proper schema and correlation inheritance
      event = UniversalEvent.new(
        event_type: 'data.change',
        action: "#{self.class.model_name.singular}.#{action}",
        actor: extract_actor,
        subject: extract_subject,
        metadata: build_change_metadata(action, changes, previous_attributes),
        timestamp: Time.now,
        correlation_id: EzlogsRubyAgent::CorrelationManager.current_context&.correlation_id
      )

      # Log the event
      EzlogsRubyAgent.writer.log(event)
    rescue StandardError => e
      warn "[Ezlogs] Failed to create callback event: #{e.message}"
    end

    def extract_actor
      ActorExtractor.extract_actor(self)
    end

    def extract_subject
      {
        type: self.class.model_name.singular,
        id: respond_to?(:id) ? id.to_s : nil,
        table: self.class.table_name
      }.compact
    end

    def build_change_metadata(action, changes, previous_attributes)
      # Get current HTTP context if available
      current_context = EzlogsRubyAgent::CorrelationManager.current_context

      metadata = {
        model: {
          class: self.class.name,
          table: self.class.table_name,
          primary_key: self.class.primary_key || 'id',
          record_id: id&.to_s
        },
        operation: action,
        changes: build_enhanced_changes(changes),
        trigger: extract_trigger_context,
        context: extract_session_context(current_context)
      }

      # Add validation errors if present
      if respond_to?(:errors) && errors.respond_to?(:any?) && errors.any? && errors.respond_to?(:full_messages)
        metadata[:validation_errors] = errors.full_messages
      end

      # Add bulk operation context if present
      if respond_to?(:bulk_operation?) && bulk_operation?
        metadata[:bulk_operation] = true
        metadata[:bulk_size] = respond_to?(:bulk_size) ? bulk_size : nil
      end

      # Add transaction context
      metadata[:transaction_id] = extract_transaction_id

      metadata.compact
    end

    def build_enhanced_changes(changes)
      return {} unless changes.is_a?(Hash)

      enhanced_changes = {}
      sensitive_fields = EzlogsRubyAgent.config.security&.sensitive_fields || []

      changes.each do |field_name, change_data|
        field_str = field_name.to_s

        # Determine if field is sensitive
        is_sensitive = sensitive_fields.any? { |sf| field_str.downcase.include?(sf.downcase) } ||
                       contains_pii?(change_data)

        if change_data.is_a?(Array) && change_data.size == 2
          # Standard Rails change format [from, to]
          from_value, to_value = change_data

          enhanced_changes[field_name] = {
            from: is_sensitive ? '[REDACTED]' : from_value,
            to: is_sensitive ? '[REDACTED]' : to_value,
            data_type: detect_data_type(to_value),
            sensitive: is_sensitive
          }
        else
          # Single value change (create/destroy)
          enhanced_changes[field_name] = {
            value: is_sensitive ? '[REDACTED]' : change_data,
            data_type: detect_data_type(change_data),
            sensitive: is_sensitive
          }
        end
      end

      enhanced_changes
    end

    def extract_trigger_context
      # Try to extract the current controller/action context
      if defined?(Rails) && Rails.application
        controller_info = extract_controller_context
        return controller_info if controller_info
      end

      # Fallback to call stack analysis
      caller_info = extract_caller_context

      {
        type: 'callback',
        hook: extract_callback_type,
        source: caller_info
      }.compact
    end

    def extract_controller_context
      # Try to get current controller from thread or request context
      current_thread = Thread.current

      # Check for Rails controller in thread
      if current_thread[:current_controller]
        controller = current_thread[:current_controller]
        return {
          type: 'http_request',
          controller: controller.class.name,
          action: controller.action_name,
          method: controller.request.method,
          endpoint: "#{controller.request.method} #{controller.request.path}"
        }
      end

      # Check correlation context for HTTP info
      current_context = EzlogsRubyAgent::CorrelationManager.current_context
      if current_context&.request_id
        return {
          type: 'http_request',
          request_id: current_context.request_id,
          session_id: current_context.session_id
        }
      end

      nil
    end

    def extract_caller_context
      # Analyze call stack to identify the source
      relevant_caller = caller.find { |line| line.include?('app/') && !line.include?('ezlogs') }

      # Parse caller line: /path/file.rb:line:in `method'
      if relevant_caller && relevant_caller.match(%r{([^/]+\.rb):(\d+):in `([^']+)'})
        return {
          file: ::Regexp.last_match(1),
          line: ::Regexp.last_match(2).to_i,
          method: ::Regexp.last_match(3)
        }
      end

      nil
    end

    def extract_callback_type
      # Determine which callback triggered this event
      case caller.find { |line| line.include?('log_') }&.match(/log_(\w+)_event/)&.[](1)
      when 'create'
        'after_create'
      when 'update'
        'after_update'
      when 'destroy'
        'after_destroy'
      else
        'unknown'
      end
    end

    def extract_session_context(current_context)
      context = {}

      # Extract from correlation context
      if current_context
        context[:request_id] = current_context.request_id if current_context.request_id
        context[:session_id] = current_context.session_id if current_context.session_id
        context[:correlation_id] = current_context.correlation_id if current_context.correlation_id
      end

      # Extract user context if available
      context[:user_id] = user_id if respond_to?(:user_id) && user_id

      # Extract environment info
      context[:environment] = {
        rails_env: defined?(Rails) ? Rails.env : ENV['RACK_ENV'] || ENV['RAILS_ENV'],
        app_version: extract_app_version,
        gem_version: EzlogsRubyAgent::VERSION
      }.compact

      # Extract IP address if available from current thread
      context[:ip_address] = Thread.current[:current_request_ip] if Thread.current[:current_request_ip]

      # Extract user agent if available
      context[:user_agent] = Thread.current[:current_user_agent] if Thread.current[:current_user_agent]

      context.compact
    end

    def detect_data_type(value)
      case value
      when String
        'string'
      when Integer
        'integer'
      when Float
        'float'
      when TrueClass, FalseClass
        'boolean'
      when Time, DateTime, Date
        'datetime'
      when NilClass
        'null'
      when Hash
        'hash'
      when Array
        'array'
      else
        'unknown'
      end
    end

    def contains_pii?(value)
      return false unless value.is_a?(String) || (value.is_a?(Array) && value.any? { |v| v.is_a?(String) })

      # Common PII patterns
      pii_patterns = [
        /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, # email
        /\b(?:\d{4}[-\s]?){3}\d{4}\b/, # credit card
        /\b\d{3}-?\d{2}-?\d{4}\b/, # SSN
        /\b\(?(\d{3})\)?[-.\s]?(\d{3})[-.\s]?(\d{4})\b/ # phone
      ]

      values_to_check = value.is_a?(Array) ? value.select { |v| v.is_a?(String) } : [value]

      values_to_check.any? do |str|
        pii_patterns.any? { |pattern| str.match?(pattern) }
      end
    end

    def extract_app_version
      # Try multiple ways to get app version
      return Rails.application.config.version if defined?(Rails) && Rails.application&.config&.respond_to?(:version)
      return ENV['APP_VERSION'] if ENV['APP_VERSION']

      # Try to read from VERSION file
      version_file = File.join(Dir.pwd, 'VERSION')
      return File.read(version_file).strip if File.exist?(version_file)

      # Try to read from Gemfile.lock for app version
      gemfile_lock = File.join(Dir.pwd, 'Gemfile.lock')
      if File.exist?(gemfile_lock)
        content = File.read(gemfile_lock)
        # Look for Rails version as proxy
        return "rails-#{::Regexp.last_match(1)}" if content.match(/rails \(([^)]+)\)/)
      end

      'unknown'
    rescue StandardError
      'unknown'
    end

    def extract_transaction_id
      # Extract transaction ID from connection
      connection = ActiveRecord::Base.connection
      if connection.respond_to?(:transaction_id)
        connection.transaction_id
      else
        "txn_#{SecureRandom.urlsafe_base64(8)}"
      end
    rescue StandardError
      "txn_#{SecureRandom.urlsafe_base64(8)}"
    end

    # Rails 5.2+ compatibility methods
    def saved_changes
      respond_to?(:saved_changes) ? super : previous_changes
    end

    def saved_attributes
      respond_to?(:saved_attributes) ? super : attributes_was
    end

    def attributes_was
      respond_to?(:attributes_was) ? super : attributes
    end
  end
end
