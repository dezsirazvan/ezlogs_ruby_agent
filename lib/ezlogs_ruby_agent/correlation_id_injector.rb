module EzlogsRubyAgent
  class CorrelationIdInjector
    def self.inject!(job)
      job['correlation_id'] ||= Thread.current[:correlation_id] || SecureRandom.uuid
    end
  end
end
