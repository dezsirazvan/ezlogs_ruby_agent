require 'ezlogs_ruby_agent/railtie' if defined?(Rails)
require 'ezlogs_ruby_agent/configuration'
require 'ezlogs_ruby_agent/jobs/event_sender_job'

module EzlogsRubyAgent
  def self.configure
    @config ||= EzlogsRubyAgent::Configuration.new
    yield(@config) if block_given?
    @config
  end

  def self.config
    @config ||= EzlogsRubyAgent::Configuration.new
  end
end