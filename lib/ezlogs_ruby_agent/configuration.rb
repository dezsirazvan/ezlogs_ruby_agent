module EzlogsRubyAgent
  class Configuration
    attr_accessor(
      :capture_http, 
      :capture_callbacks, 
      :capture_jobs,     
      :resources_to_track, 
      :exclude_resources,
    )

    def initialize
      @capture_http = true
      @capture_callbacks = true
      @capture_jobs = true
      @resources_to_track = []
      @exclude_resources = ['EzlogsRubyAgent', 'queue']
    end
  end
end
