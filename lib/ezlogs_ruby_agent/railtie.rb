require 'rails/railtie'
require 'ezlogs_ruby_agent/callbacks_tracker'
require 'ezlogs_ruby_agent/http_tracker'
require 'ezlogs_ruby_agent/job_tracker'

module EzlogsRubyAgent
  class Railtie < ::Rails::Railtie
    initializer "ezlogs_ruby_agent.configure" do |app|
      EzlogsRubyAgent.configure do |config|
        config.capture_http = true
        config.capture_callbacks = true
        config.capture_jobs = true
        config.models_to_track = [] # Track all models if empty
        config.exclude_models = []  # Exclude specific models
      end
    end

    initializer "ezlogs_ruby_agent.include_modules" do
      ActiveSupport.on_load(:active_record) do
        include EzlogsRubyAgent::CallbacksTracker if EzlogsRubyAgent.config.capture_callbacks
      end

      ActiveSupport.on_load(:action_controller) do
        if EzlogsRubyAgent.config.capture_http
          Rails.application.config.middleware.use EzlogsRubyAgent::HttpTracker
        end
      end

      ActiveSupport.on_load(:active_job) do
        prepend EzlogsRubyAgent::JobTracker if EzlogsRubyAgent.config.capture_jobs
      end
    end
  end
end
