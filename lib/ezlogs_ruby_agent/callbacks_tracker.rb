module EzlogsRubyAgent
  module CallbacksTracker
    extend ActiveSupport::Concern

    included do
      after_create :log_create_event
      after_update :log_update_event
      after_destroy :log_destroy_event
    end

    private

    def log_create_event
      EzlogsRubyAgent::EventQueue.add({
        type: "model_callback",
        action: "create",
        model: self.class.name,
        changes: attributes,
        timestamp: Time.current
      })
    end

    def log_update_event
      EzlogsRubyAgent::EventQueue.add({
        type: "model_callback",
        action: "update",
        model: self.class.name,
        changes: previous_changes,
        timestamp: Time.current
      })
    end

    def log_destroy_event
      EzlogsRubyAgent::EventQueue.add({
        type: "model_callback",
        action: "destroy",
        model: self.class.name,
        changes: attributes,
        timestamp: Time.current
      })
    end
  end
end
