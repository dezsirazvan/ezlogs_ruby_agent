require 'ezlogs_ruby_agent/railtie' if defined?(Rails)
require 'ezlogs_ruby_agent/configuration'
require 'ezlogs_ruby_agent/jobs/event_sender_job'
require 'ezlogs_ruby_agent/event_writer'

module EzlogsRubyAgent
  class << self
    def configure
      @config ||= Configuration.new
      yield(@config) if block_given?
      @config
    end

    def config
      @config ||= Configuration.new
    end

    def writer
      @writer ||= EventWriter.new
    end
  end
end