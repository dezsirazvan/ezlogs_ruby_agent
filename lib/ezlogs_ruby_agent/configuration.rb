module EzlogsRubyAgent
  class Configuration
    attr_accessor :capture_http, :capture_callbacks, :capture_jobs,
                  :models_to_track, :exclude_models, :batch_size, :endpoint_url

    def initialize
      @capture_http = true
      @capture_callbacks = true
      @capture_jobs = true
      @models_to_track = []
      @exclude_models = []
      @batch_size = 100
      @endpoint_url = "https://api.ezlogs.com/events"
    end
  end
end
