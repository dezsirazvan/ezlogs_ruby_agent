module EzlogsRubyAgent
  class CorrelationIdInjector
    def self.inject!(job)
      correlation_id = Thread.current[:correlation_id] || SecureRandom.uuid
      job['correlation_id'] = correlation_id
    end
  end
end
