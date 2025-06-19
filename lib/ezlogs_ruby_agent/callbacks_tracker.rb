require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'

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
      event = UniversalEvent.new(
        event_type: "resource_callback",
        resource: self.class.name,
        resource_id: respond_to?(:id) ? id : nil,
        action: action,
        actor: ActorExtractor.extract_actor(self),
        timestamp: Time.now,
        metadata: changes
      )

      EzlogsRubyAgent.writer.log(event.to_h)
    rescue StandardError => e
      warn "[Ezlogs] failed to create callback event: #{e.message}"
    end
  end
end
