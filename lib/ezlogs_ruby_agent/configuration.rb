module EzlogsRubyAgent
  class Configuration
    attr_accessor :capture_http, :capture_callbacks, :capture_jobs,
                  :resources_to_track, :exclude_resources, :batch_size, :endpoint_url,
                  :job_adapter, :background_jobs_queue

    def initialize
      @capture_http = true
      @capture_callbacks = true
      @capture_jobs = true
      @resources_to_track = []
      @exclude_resources = ['EzlogsRubyAgent', 'queue']
      @batch_size = 100
      @endpoint_url = "https://api.ezlogs.com/events"
      @job_adapter = :sidekiq
      @background_jobs_queue = 'default'
    end
  end
end
