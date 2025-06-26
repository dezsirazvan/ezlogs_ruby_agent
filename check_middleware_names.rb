require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'rails', '~> 7.0'
  gem 'ezlogs_ruby_agent', path: '/Users/razvicul/Desktop/ezlogs_ruby_agent'
end

require 'rails'
require 'ezlogs_ruby_agent'

# Create a minimal Rails app
module TestApp
  class Application < Rails::Application
    config.load_defaults 7.0
    config.eager_load = false
    config.logger = Logger.new(STDOUT)
    config.log_level = :info
  end
end

# Initialize EzLogs
EzlogsRubyAgent.configure do |config|
  config.service_name = 'test_app'
  config.environment = 'development'
  config.delivery.endpoint = 'https://api.example.com/events'
end

# Initialize Rails
Rails.application.initialize!

# Check middleware names
puts "\n=== MIDDLEWARE STACK WITH NAMES ==="
Rails.application.middleware.each_with_index do |middleware, index|
  klass = middleware.instance_variable_get(:@klass)
  puts "#{index}: #{klass}"
end

puts "\n=== LOOKING FOR EZLOGS ==="
found_ezlogs = false
Rails.application.middleware.each_with_index do |middleware, index|
  klass = middleware.instance_variable_get(:@klass)
  if klass.to_s.include?('Ezlogs') || klass.to_s.include?('EzLogs') || klass.to_s.include?('HttpTracker')
    puts "Found EzLogs middleware at #{index}: #{klass}"
    found_ezlogs = true
  end
end

unless found_ezlogs
  puts "No EzLogs middleware found!"
end
