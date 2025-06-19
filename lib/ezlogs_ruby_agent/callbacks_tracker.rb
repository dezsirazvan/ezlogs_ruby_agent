require 'active_support/concern'
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

      resource_inclusion = config.resources_to_track.empty? ||
                           config.resources_to_track.any? { |resource| resource.match?(resource_name) }
      resource_exclusion = config.exclude_resources.any? { |resource| resource.match?(resource_name) }

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
        action: "#{model_name.singular}.#{action}",
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
        type: model_name.singular,
        id: respond_to?(:id) ? id.to_s : nil,
        table: table_name
      }.compact
    end

    def build_change_metadata(action, changes, previous_attributes)
      metadata = {
        action: action,
        model: model_name.singular,
        table: table_name,
        changes: sanitize_changes(changes),
        timestamp: Time.now.iso8601
      }

      # Add previous attributes for updates
      if action == 'update' && previous_attributes
        metadata[:previous_attributes] = sanitize_attributes(previous_attributes)
      end

      # Add validation errors if any
      metadata[:validation_errors] = errors.full_messages if respond_to?(:errors) && errors.any?

      # Add bulk operation context
      if respond_to?(:bulk_operation?) && bulk_operation?
        metadata[:bulk_operation] = true
        metadata[:bulk_size] = bulk_size if respond_to?(:bulk_size)
      end

      # Add transaction context
      if defined?(ActiveRecord) && ActiveRecord::Base.connection.transaction_open?
        metadata[:transaction_id] =
          extract_transaction_id
      end

      metadata
    end

    def sanitize_changes(changes)
      return {} unless changes.is_a?(Hash)

      sensitive_fields = EzlogsRubyAgent.config.security.sanitize_fields

      changes.transform_values do |change|
        if change.is_a?(Array) && change.size == 2
          # Handle before/after changes
          [
            sanitize_value(change[0], sensitive_fields),
            sanitize_value(change[1], sensitive_fields)
          ]
        else
          sanitize_value(change, sensitive_fields)
        end
      end
    end

    def sanitize_attributes(attributes)
      return {} unless attributes.is_a?(Hash)

      sensitive_fields = EzlogsRubyAgent.config.security.sanitize_fields

      attributes.transform_values do |value|
        sanitize_value(value, sensitive_fields)
      end
    end

    def sanitize_value(value, sensitive_fields)
      return value unless value.is_a?(String)

      # Check if this field should be sanitized
      field_name = caller_locations(1, 1)[0].label
      if sensitive_fields.any? { |field| field_name.downcase.include?(field.downcase) }
        '[REDACTED]'
      else
        value
      end
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

    def model_name
      OpenStruct.new(singular: self.class.name.underscore)
    end

    def table_name
      self.class.table_name
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
