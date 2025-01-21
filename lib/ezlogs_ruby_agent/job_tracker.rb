module EzlogsRubyAgent
  module JobTracker
    def perform(*args)
      start_time = Time.current
      super
      end_time = Time.current

      EzlogsRubyAgent::EventQueue.add({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "completed",
        duration: (end_time - start_time).to_f,
        timestamp: Time.current
      })
    rescue => e
      EzlogsRubyAgent::EventQueue.add({
        type: "background_job",
        job_name: self.class.name,
        arguments: args,
        status: "failed",
        error: e.message,
        timestamp: Time.current
      })
      raise e
    end
  end
end
