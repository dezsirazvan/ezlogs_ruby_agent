module EzlogsRubyAgent
  class Configuration
    attr_accessor(
      :capture_http,           # Should HTTP requests be tracked?
      :capture_callbacks,      # Should ActiveRecord callbacks be tracked?
      :capture_jobs,           # Should background jobs be tracked?
      :resources_to_track,     # List of resource types to track
      :exclude_resources,      # List of resource types to exclude
      :actor_extractor         # Optional: Custom actor extractor method (e.g., a proc)
    )

    def initialize
      @capture_http = true
      @capture_callbacks = true
      @capture_jobs = true
      @resources_to_track = []    # Can add specific classes or regex patterns
      @exclude_resources = []     # Resources to exclude from tracking
      @actor_extractor = nil      # Can be set to a custom proc if needed
    end
  end
end
