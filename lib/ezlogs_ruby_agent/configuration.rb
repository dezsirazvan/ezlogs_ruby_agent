module EzlogsRubyAgent
  class Configuration
    attr_accessor :capture_http, :capture_callbacks, :capture_jobs,
                  :models_to_track, :exclude_models, :batch_size, :endpoint_url,
                  :job_adapter, :background_jobs_queue

    def initialize
      @capture_http = true
      @capture_callbacks = true
      @capture_jobs = true
      @models_to_track = []
      @exclude_models = ['EzlogsRubyAgent', 'queue']
      @batch_size = 100
      @endpoint_url = "https://api.ezlogs.com/events"
      @job_adapter = :sidekiq
      @background_jobs_queue = 'default'
    end
  end
end
