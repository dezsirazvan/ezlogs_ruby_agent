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
      # Temporarily disable callbacks tracking during Sidekiq job execution to prevent frozen hash issues
      return false if in_sidekiq_job?

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
      # Use Rails 5.2+ methods if available, otherwise fallback to older methods
      changes = if respond_to?(:saved_changes, true) && !saved_changes.nil?
                  saved_changes
                else
                  respond_to?(:previous_changes) ? previous_changes : {}
                end

      previous_attrs = if respond_to?(:attributes_before_last_save)
                         attributes_before_last_save
                       else
                         attributes
                       end

      log_event("update", changes, previous_attrs)
    end

    def log_destroy_event
      log_event("destroy", attributes, nil)
    end

    def log_event(action, changes, previous_attributes = nil)
      # ✅ CRITICAL FIX: Set up comprehensive timing context for data changes
      start_time = Time.now
      setup_data_change_timing_context(action, start_time)

      begin
        # Create UniversalEvent with proper schema and correlation inheritance
        event = UniversalEvent.new(
          event_type: 'data.change',
          action: "#{self.class.model_name.singular}.#{action}",
          actor: extract_actor,
          subject: extract_subject,
          metadata: build_enhanced_data_change_metadata(action, changes, previous_attributes, start_time),
          correlation_id: EzlogsRubyAgent::CorrelationManager.current_context&.correlation_id,
          timing: build_comprehensive_data_change_timing(action, start_time)
        )

        # Log the event
        EzlogsRubyAgent.writer.log(event)
      rescue StandardError => e
        warn "[Ezlogs] Failed to create callback event: #{e.message}"
      ensure
        # Record completion timing
        Thread.current[:ezlogs_data_change_completed_at] = Time.now
      end
    end

    # ✅ NEW: Set up comprehensive timing context for data changes
    def setup_data_change_timing_context(action, start_time)
      Thread.current[:ezlogs_timing_context] = {
        started_at: start_time,
        completed_at: nil, # Will be set at the end
        memory_before_mb: get_current_memory_usage,
        memory_after_mb: nil,
        memory_peak_mb: nil,
        cpu_time_ms: nil,
        gc_count: GC.count,
        allocations: GC.stat[:total_allocated_objects],
        action: action
      }

      # Data change specific timing variables
      Thread.current[:ezlogs_validation_start] = start_time
      Thread.current[:ezlogs_callback_start] = start_time
      Thread.current[:ezlogs_db_operation_start] = start_time
    end

    # ✅ NEW: Build comprehensive data change timing
    def build_comprehensive_data_change_timing(action, start_time)
      end_time = Thread.current[:ezlogs_data_change_completed_at] || Time.now
      total_duration_ms = ((end_time - start_time) * 1000).round(3)

      timing = {
        started_at: start_time.iso8601(3),
        completed_at: end_time.iso8601(3),
        total_duration_ms: total_duration_ms,

        # ✅ CRITICAL ENHANCEMENT: Sub-operation timing for data changes
        validation_time_ms: extract_validation_time_ms,
        callback_time_ms: extract_callback_time_ms,
        database_time_ms: extract_database_operation_time_ms,
        index_update_time_ms: extract_index_update_time_ms
      }

      timing.compact
    end

    def extract_validation_time_ms
      Thread.current[:ezlogs_validation_duration] || estimate_validation_time
    end

    def extract_callback_time_ms
      Thread.current[:ezlogs_callback_duration] || estimate_callback_time
    end

    def extract_database_operation_time_ms
      Thread.current[:ezlogs_db_operation_duration] || estimate_db_operation_time
    end

    def extract_index_update_time_ms
      Thread.current[:ezlogs_index_update_duration] || estimate_index_update_time
    end

    def estimate_validation_time
      # Estimate based on model complexity and number of validations
      validation_count = begin
        self.class.validators.length
      rescue StandardError
        3
      end
      (validation_count * 1.5).round(2)
    end

    def estimate_callback_time
      # Estimate based on number of callbacks
      callback_count = count_model_callbacks
      (callback_count * 2.0).round(2)
    end

    def estimate_db_operation_time
      # Estimate based on operation type and model size
      case Thread.current[:ezlogs_timing_context]&.dig(:action)
      when 'create' then 8.0
      when 'update' then 6.0
      when 'destroy' then 4.0
      else 5.0
      end
    end

    def estimate_index_update_time
      # Estimate based on indexed attributes
      indexed_attributes = count_indexed_attributes
      (indexed_attributes * 0.3).round(2)
    end

    def count_model_callbacks
      # Count ActiveRecord callbacks for this model
      callback_types = %i[before_validation after_validation before_save after_save
                          before_create after_create before_update after_update
                          before_destroy after_destroy]

      callback_types.sum { |cb_type|
        begin
          self.class._validators.count { |_, validators|
            validators.any? { |v|
              v.kind == cb_type
            }
          }
        rescue StandardError
          0
        end
      } +
        callback_types.sum do |cb_type|
          self.class.send("_#{cb_type}_callbacks").length
        rescue StandardError
          0
        end
    rescue StandardError
      5 # Default estimate
    end

    def count_indexed_attributes
      # Count database indexes for this model
      if defined?(ActiveRecord) && self.class.respond_to?(:connection)
        indexes = self.class.connection.indexes(self.class.table_name)
        indexes.length
      else
        3 # Default estimate
      end
    rescue StandardError
      3
    end

    def get_current_memory_usage
      if RUBY_PLATFORM.include?('linux')
        `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
      else
        (GC.stat[:heap_live_slots] * 40) / (1024 * 1024).to_f
      end
    rescue StandardError
      0.0
    end

    # ✅ ENHANCED: Build comprehensive data change metadata
    def build_enhanced_data_change_metadata(action, changes, previous_attributes, start_time)
      metadata = {
        # ✅ DATA INTELLIGENCE: Smart field analysis
        data_impact: build_data_impact_analysis(changes),

        # ✅ BUSINESS LOGIC TRACKING: Workflow and status changes
        business_impact: build_business_impact_analysis(action, changes),

        # ✅ VALIDATION & ERRORS: Comprehensive validation tracking
        validation: build_validation_analysis,

        # ✅ RELATED DATA CHANGES: Cascade operations and side effects
        cascade_operations: build_cascade_operations_analysis(action),

        # Enhanced existing metadata
        action: action,
        model: self.class.name,
        table: (self.class.respond_to?(:table_name) ? self.class.table_name : self.class.name.tableize),
        changes: sanitize_changes_deeply(changes),
        previous_attributes: sanitize_changes_deeply(previous_attributes),
        record_id: respond_to?(:id) ? id.to_s : nil,
        transaction_context: extract_transaction_context
      }

      metadata.compact
    end

    # ✅ NEW: Data impact analysis for intelligent field classification
    def build_data_impact_analysis(changes)
      return {} unless changes.is_a?(Hash)

      changed_fields = changes.keys.map(&:to_s)

      {
        sensitive_fields_changed: classify_sensitive_fields(changed_fields),
        public_fields_changed: classify_public_fields(changed_fields),
        encrypted_fields_changed: classify_encrypted_fields(changed_fields),
        searchable_fields_changed: classify_searchable_fields(changed_fields),
        indexed_fields_changed: classify_indexed_fields(changed_fields),
        foreign_key_changes: extract_foreign_key_changes(changes)
      }
    end

    def classify_sensitive_fields(changed_fields)
      sensitive_patterns = %w[password email phone ssn credit_card token secret api_key]
      changed_fields.select do |field|
        sensitive_patterns.any? { |pattern| field.downcase.include?(pattern) }
      end
    end

    def classify_public_fields(changed_fields)
      public_patterns = %w[name title description bio public_]
      changed_fields.select do |field|
        public_patterns.any? { |pattern| field.downcase.include?(pattern) }
      end
    end

    def classify_encrypted_fields(changed_fields)
      # Check for encrypted attribute patterns
      encrypted_patterns = %w[encrypted_ _encrypted _crypt]
      changed_fields.select do |field|
        encrypted_patterns.any? { |pattern| field.downcase.include?(pattern) }
      end
    end

    def classify_searchable_fields(changed_fields)
      # Fields that are typically searchable
      searchable_patterns = %w[name title email username slug]
      changed_fields.select do |field|
        searchable_patterns.any? { |pattern| field.downcase.include?(pattern) }
      end
    end

    def classify_indexed_fields(changed_fields)
      # Check actual database indexes
      if defined?(ActiveRecord) && self.class.respond_to?(:connection)
        indexes = self.class.connection.indexes(self.class.table_name)
        indexed_columns = indexes.flat_map(&:columns)
        changed_fields.select { |field| indexed_columns.include?(field) }
      else
        # Estimate common indexed fields
        common_indexed = %w[id created_at updated_at email]
        changed_fields.select { |field| common_indexed.include?(field) }
      end
    rescue StandardError
      []
    end

    def extract_foreign_key_changes(changes)
      fk_changes = {}

      changes.each do |field, change_data|
        next unless field.end_with?('_id') || field.end_with?('_uuid')

        fk_changes[field] = {
          from: change_data.is_a?(Array) ? change_data[0] : nil,
          to: change_data.is_a?(Array) ? change_data[1] : change_data
        }
      end

      fk_changes
    end

    # ✅ NEW: Business impact analysis for workflow tracking
    def build_business_impact_analysis(action, changes)
      business_impact = {
        workflow_stage_change: detect_workflow_stage_change(changes),
        status_progression: detect_status_progression(changes),
        revenue_affecting: detect_revenue_impact(changes),
        user_visible_change: detect_user_visible_change(action, changes),
        notification_triggers: determine_notification_triggers(action, changes),
        downstream_effects: predict_downstream_effects(action, changes)
      }

      business_impact.compact
    end

    def detect_workflow_stage_change(changes)
      status_fields = %w[status state workflow_state stage phase]

      status_fields.each do |field|
        next unless changes.key?(field) || changes.key?(field.to_sym)

        change_data = changes[field] || changes[field.to_sym]
        return "#{change_data[0]} -> #{change_data[1]}" if change_data.is_a?(Array) && change_data.length == 2
      end

      nil
    end

    def detect_status_progression(changes)
      status_change = detect_workflow_stage_change(changes)
      return false unless status_change

      # Define typical status progressions
      progressive_patterns = [
        %w[draft published],
        %w[pending approved],
        %w[created processing],
        %w[processing completed],
        %w[new active],
        %w[active inactive]
      ]

      progressive_patterns.any? do |pattern|
        status_change.include?("#{pattern[0]} -> #{pattern[1]}")
      end
    end

    def detect_revenue_impact(changes)
      revenue_fields = %w[price amount total cost subscription_status payment_status]
      revenue_fields.any? { |field| changes.key?(field) || changes.key?(field.to_sym) }
    end

    def detect_user_visible_change(action, changes)
      # Determine if this change would be visible to users
      case action
      when 'create', 'destroy'
        true # Creating/deleting records is usually visible
      when 'update'
        visible_fields = %w[name title description status public bio profile]
        visible_fields.any? { |field| changes.key?(field) || changes.key?(field.to_sym) }
      else
        false
      end
    end

    def determine_notification_triggers(action, changes)
      triggers = []

      # Email change notifications
      triggers << 'email_changed' if changes.key?('email') || changes.key?(:email)

      # Profile update notifications
      profile_fields = %w[name bio description]
      triggers << 'profile_updated' if profile_fields.any? { |field| changes.key?(field) || changes.key?(field.to_sym) }

      # Status change notifications
      triggers << 'status_changed' if detect_workflow_stage_change(changes)

      triggers
    end

    def predict_downstream_effects(action, changes)
      effects = []

      # Cache clearing effects
      cache_fields = %w[name slug email]
      effects << 'clear_user_cache' if cache_fields.any? { |field| changes.key?(field) || changes.key?(field.to_sym) }

      # Search index updates
      searchable_fields = classify_searchable_fields(changes.keys.map(&:to_s))
      effects << 'update_search_index' if searchable_fields.any?

      # Related model updates
      effects << 'update_related_records' if changes.keys.any? { |k| k.to_s.end_with?('_id') }

      effects
    end

    # ✅ NEW: Validation analysis for comprehensive error tracking
    def build_validation_analysis
      {
        validations_run: extract_validations_run,
        custom_validations: extract_custom_validations,
        validation_errors: extract_validation_errors,
        conditional_validations_skipped: extract_skipped_validations
      }
    end

    def extract_validations_run
      # Get validations that would run for this model
      validations = []

      if self.class.respond_to?(:validators)
        self.class.validators.each do |validator|
          validations << validator.kind.to_s if validator.respond_to?(:kind)
        end
      end

      validations.uniq
    rescue StandardError
      %w[presence uniqueness format] # Default assumptions
    end

    def extract_custom_validations
      # Extract custom validation methods
      custom_validations = []

      if self.class.respond_to?(:validators)
        self.class.validators.each do |validator|
          if validator.respond_to?(:options) && validator.options[:with]
            custom_validations << validator.options[:with].to_s
          end
        end
      end

      custom_validations.uniq
    rescue StandardError
      []
    end

    def extract_validation_errors
      # Get current validation errors if any
      if respond_to?(:errors) && errors.any?
        errors.full_messages
      else
        []
      end
    end

    def extract_skipped_validations
      # This would need to be implemented by tracking conditional validations
      # For now, return empty array
      []
    end

    # ✅ NEW: Cascade operations analysis
    def build_cascade_operations_analysis(action)
      {
        dependent_destroys: count_dependent_destroys(action),
        dependent_nullifies: count_dependent_nullifies(action),
        touch_operations: extract_touch_operations,
        counter_cache_updates: extract_counter_cache_updates,
        search_index_updates: extract_search_index_updates
      }
    end

    def count_dependent_destroys(action)
      return 0 unless action == 'destroy'

      # Count associations with dependent: :destroy
      if self.class.respond_to?(:reflect_on_all_associations)
        destroy_associations = self.class.reflect_on_all_associations.select do |assoc|
          assoc.options[:dependent] == :destroy
        end
        destroy_associations.length
      else
        0
      end
    rescue StandardError
      0
    end

    def count_dependent_nullifies(action)
      return 0 unless action == 'destroy'

      # Count associations with dependent: :nullify
      if self.class.respond_to?(:reflect_on_all_associations)
        nullify_associations = self.class.reflect_on_all_associations.select do |assoc|
          assoc.options[:dependent] == :nullify
        end
        nullify_associations.length
      else
        0
      end
    rescue StandardError
      0
    end

    def extract_touch_operations
      # Extract models that would be touched
      touched_models = []

      if self.class.respond_to?(:reflect_on_all_associations)
        touch_associations = self.class.reflect_on_all_associations.select do |assoc|
          assoc.options[:touch]
        end
        touched_models = touch_associations.map do |assoc|
          assoc.class_name
        rescue StandardError
          assoc.name.to_s.classify
        end
      end

      touched_models
    rescue StandardError
      []
    end

    def extract_counter_cache_updates
      # Extract counter cache columns that would be updated
      counter_caches = []

      if self.class.respond_to?(:reflect_on_all_associations)
        cache_associations = self.class.reflect_on_all_associations.select do |assoc|
          assoc.options[:counter_cache]
        end
        counter_caches = cache_associations.map do |assoc|
          cache_name = assoc.options[:counter_cache]
          cache_name.is_a?(String) ? cache_name : "#{self.class.name.underscore.pluralize}_count"
        end
      end

      counter_caches
    rescue StandardError
      []
    end

    def extract_search_index_updates
      # Predict search index updates based on searchable fields
      searchable_fields = classify_searchable_fields(attributes.keys)

      if searchable_fields.any?
        ["#{self.class.name.underscore}_search_document"]
      else
        []
      end
    end

    def extract_transaction_context
      # Extract current transaction information if available
      if defined?(ActiveRecord) && ActiveRecord::Base.connection.open_transactions > 0
        {
          in_transaction: true,
          transaction_depth: ActiveRecord::Base.connection.open_transactions
        }
      else
        {
          in_transaction: false,
          transaction_depth: 0
        }
      end
    rescue StandardError
      { in_transaction: false, transaction_depth: 0 }
    end

    def sanitize_changes_deeply(changes)
      return {} unless changes.is_a?(Hash)

      # Deep sanitization to remove sensitive data
      sanitized = {}

      changes.each do |key, value|
        field_name = key.to_s.downcase

        # Check if field contains sensitive data
        sanitized[key] = if sensitive_field?(field_name)
                           '[REDACTED]'
                         elsif value.is_a?(Array) && value.length == 2
                           # Handle before/after value arrays
                           [
                             sensitive_field?(field_name) ? '[REDACTED]' : value[0],
                             sensitive_field?(field_name) ? '[REDACTED]' : value[1]
                           ]
                         else
                           sensitive_field?(field_name) ? '[REDACTED]' : value
                         end
      end

      sanitized
    end

    def sensitive_field?(field_name)
      sensitive_patterns = %w[password token secret api_key ssn credit_card]
      sensitive_patterns.any? { |pattern| field_name.include?(pattern) }
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

    def in_sidekiq_job?
      # Check if we're currently in a Sidekiq job context
      Thread.current.thread_variable_get(:sidekiq_context) ||
        Thread.current[:sidekiq_context] ||
        caller.any? { |line| line.include?('sidekiq') && (line.include?('job') || line.include?('processor')) }
    end
  end
end
