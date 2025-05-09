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

      (
        config.resources_to_track.empty? || 
        config.resources_to_track.map(&:downcase).include?(resource_name.downcase)
      ) &&
        !config.exclude_resources.include?(resource_name.downcase)
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
      # resource_id = id

      # EzlogsRubyAgent::EventQueue.instance.add({
      #   type: "resource_callback",
      #   action: action,
      #   resource: self.class.name,
      #   changes: changes,
      #   resource_id: resource_id,
      #   timestamp: Time.current
      # })
    end
  end
end
