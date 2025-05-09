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
      log_event("create", attributes)
    end

    def log_update_event
      log_event("update", previous_changes)
    end

    def log_destroy_event
      log_event("destroy", attributes)
    end

    def log_event(action, changes)
      event_data = build_event_data(action, changes)
      EzlogsRubyAgent::EventWriter.write_event_to_log(event_data)
    end

    def build_event_data(action, changes)
      {
        event_id: SecureRandom.uuid,
        correlation_id: Thread.current[:correlation_id] || SecureRandom.uuid,
        event_type: "resource_callback",
        resource: self.class.name,
        action: action,
        actor: ActorExtractor.extract_actor(self),
        timestamp: Time.current,
        metadata: changes
      }
    end
  end
end
