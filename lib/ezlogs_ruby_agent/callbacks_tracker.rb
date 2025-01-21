require 'ezlogs_ruby_agent/event_queue'

module EzlogsRubyAgent
  module CallbacksTracker
    extend ActiveSupport::Concern

    included do
      after_create :log_create_event, if: :trackable_model?
      after_update :log_update_event, if: :trackable_model?
      after_destroy :log_destroy_event, if: :trackable_model?
    end

    private

    def trackable_model?
      config = EzlogsRubyAgent.config
      model_name = self.class.name

      (config.models_to_track.empty? || config.models_to_track.include?(model_name)) &&
        !config.exclude_models.include?(model_name)
    end

    def log_create_event
      EzlogsRubyAgent::EventQueue.instance.add({
        type: "model_callback",
        action: "create",
        model: self.class.name,
        changes: attributes,
        timestamp: Time.current
      })
    end

    def log_update_event
      EzlogsRubyAgent::EventQueue.instance.add({
        type: "model_callback",
        action: "update",
        model: self.class.name,
        changes: previous_changes,
        timestamp: Time.current
      })
    end

    def log_destroy_event
      EzlogsRubyAgent::EventQueue.instance.add({
        type: "model_callback",
        action: "destroy",
        model: self.class.name,
        changes: attributes,
        timestamp: Time.current
      })
    end
  end
end
