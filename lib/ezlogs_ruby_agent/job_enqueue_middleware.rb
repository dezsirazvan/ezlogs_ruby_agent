module EzlogsRubyAgent
  # Middleware to track job enqueue events
  class JobEnqueueMiddleware
    def call(worker_class, job, queue, redis_pool)
      # Add correlation ID to job if not present
      job['correlation_id'] ||= Thread.current[:correlation_id] || SecureRandom.uuid

      # Call the next middleware in the chain
      yield
    end
  end
end
