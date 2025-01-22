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
      log_event("create", attributes)
    end

    def log_update_event
      log_event("update", previous_changes)
    end

    def log_destroy_event
      log_event("destroy", attributes)
    end

    def log_event(action, changes)
      EzlogsRubyAgent::EventQueue.instance.add({
        type: "model_callback",
        action: action,
        model: self.class.name,
        changes: changes,
        correlation_id: Thread.current[:correlation_id],
        timestamp: Time.current
      })
    end
  end
end
