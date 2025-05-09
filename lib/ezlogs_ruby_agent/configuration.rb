module EzlogsRubyAgent
  class Configuration
    attr_accessor(
      :capture_http,        # Should HTTP requests be tracked?
      :capture_callbacks,   # Should AR callbacks be tracked?
      :capture_jobs,        # Should background jobs be tracked?
      :resources_to_track,  # List of resource types to track
      :exclude_resources,   # List of resource types to exclude
      :actor_extractor,     # Optional custom actor extractor Proc
      :agent_host,          # e.g. "127.0.0.1"
      :agent_port,          # e.g. 9000
      :flush_interval,      # in seconds, e.g. 1.0
      :max_buffer_size      # e.g. 5_000
    )

    def initialize
      @capture_http        = true
      @capture_callbacks   = true
      @capture_jobs        = true
      @resources_to_track  = []
      @exclude_resources   = []
      @actor_extractor     = nil
      @agent_host         = '127.0.0.1'
      @agent_port         = 9000
      @flush_interval     = 1.0
      @max_buffer_size    = 5_000
    end
  end
end
