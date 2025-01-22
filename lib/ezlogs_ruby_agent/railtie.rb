require 'rails/railtie'
require 'ezlogs_ruby_agent/callbacks_tracker'
require 'ezlogs_ruby_agent/http_tracker'
require 'ezlogs_ruby_agent/job_tracker'
require 'ezlogs_ruby_agent/sidekiq_job_tracker'
require 'ezlogs_ruby_agent/job_enqueue_middleware'

module EzlogsRubyAgent
  class Railtie < ::Rails::Railtie
    initializer "ezlogs_ruby_agent.configure" do |app|
      EzlogsRubyAgent.configure do |config|
      end
    end

    initializer "ezlogs_ruby_agent.insert_middleware", before: :build_middleware_stack do |app|
      app.middleware.use EzlogsRubyAgent::HttpTracker if EzlogsRubyAgent.config.capture_http
    end

    initializer "ezlogs_ruby_agent.include_modules" do
      ActiveSupport.on_load(:active_record) do
        include EzlogsRubyAgent::CallbacksTracker if EzlogsRubyAgent.config.capture_callbacks
      end

      ActiveSupport.on_load(:active_job) do
        prepend EzlogsRubyAgent::JobTracker if EzlogsRubyAgent.config.capture_jobs
      end
    end

    initializer "ezlogs_ruby_agent.configure_sidekiq" do
      if EzlogsRubyAgent.config.capture_jobs
        Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add EzlogsRubyAgent::SidekiqJobTracker
          end
          config.client_middleware do |chain|
            chain.add EzlogsRubyAgent::JobEnqueueMiddleware
          end
        end 
      end
    end

    initializer "ezlogs_ruby_agent.configure_jobs" do
      EzlogsRubyAgent.config.job_adapter = if defined?(Sidekiq)
                                             :sidekiq
                                           else
                                             :active_job
                                           end
    end
  end
end
