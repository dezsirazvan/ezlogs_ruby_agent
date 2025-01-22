require 'ezlogs_ruby_agent/correlation_id_injector'

module EzlogsRubyAgent
  class JobEnqueueMiddleware
    def call(worker_class, job, queue, redis_pool = nil)
      EzlogsRubyAgent::CorrelationIdInjector.inject!(job)
      super(worker_class, job, queue, redis_pool)
    end
  end
end