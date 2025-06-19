require 'ezlogs_ruby_agent/railtie' if defined?(Rails)
require 'ezlogs_ruby_agent/configuration'
require 'ezlogs_ruby_agent/universal_event'
require 'ezlogs_ruby_agent/event_processor'
require 'ezlogs_ruby_agent/delivery_engine'
require 'ezlogs_ruby_agent/event_writer'

module EzlogsRubyAgent
  def self.configure
    @config ||= Configuration.new
    yield(@config) if block_given?
    @config
  end

  def self.config
    @config ||= Configuration.new
  end

  def self.writer
    @writer ||= EventWriter.new
  end

  def self.delivery_engine
    @delivery_engine ||= DeliveryEngine.new(config)
  end

  def self.processor
    @processor ||= EventProcessor.new(
      sample_rate: config.performance.sample_rate,
      max_payload_size: config.security.max_payload_size,
      auto_detect_pii: config.security.auto_detect_pii,
      sanitize_fields: config.security.sanitize_fields,
      custom_patterns: config.security.custom_patterns
    )
  end
end