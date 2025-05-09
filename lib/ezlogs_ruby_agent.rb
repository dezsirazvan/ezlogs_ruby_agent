require 'ezlogs_ruby_agent/railtie' if defined?(Rails)
require 'ezlogs_ruby_agent/configuration'
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
end