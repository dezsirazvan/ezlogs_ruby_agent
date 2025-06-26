require 'rails/railtie'
require 'ezlogs_ruby_agent/callbacks_tracker'
require 'ezlogs_ruby_agent/http_tracker'
require 'ezlogs_ruby_agent/job_tracker'
require 'ezlogs_ruby_agent/sidekiq_job_tracker'
require 'ezlogs_ruby_agent/job_enqueue_middleware'

module EzlogsRubyAgent
  # Rails integration for EZLogs Ruby Agent
  #
  # This Railtie automatically integrates EZLogs with Rails applications,
  # providing zero-config event tracking for HTTP requests, database changes,
  # and background jobs.
  #
  # @example Automatic integration
  #   # Simply add the gem to your Gemfile
  #   gem 'ezlogs_ruby_agent'
  #
  #   # The Railtie automatically:
  #   # - Adds HTTP tracking middleware
  #   # - Includes CallbacksTracker in ActiveRecord models
  #   # - Includes JobTracker in ActiveJob classes
  #   # - Configures Sidekiq integration if available
  class Railtie < ::Rails::Railtie
    # Configure HTTP request tracking middleware
    initializer "ezlogs_ruby_agent.insert_middleware", before: :build_middleware_stack do |app|
      app.middleware.use EzlogsRubyAgent::HttpTracker if EzlogsRubyAgent.config.instrumentation.http
    end

    # Configure ActiveRecord and ActiveJob tracking
    initializer "ezlogs_ruby_agent.include_modules" do
      ActiveSupport.on_load(:active_record) do
        # :nocov:
        include EzlogsRubyAgent::CallbacksTracker if EzlogsRubyAgent.config.instrumentation.active_record
        # :nocov:
      end

      ActiveSupport.on_load(:active_job) do
        prepend EzlogsRubyAgent::JobTracker if EzlogsRubyAgent.config.instrumentation.active_job
      end
    end

    # Configure Sidekiq integration if available
    initializer "ezlogs_ruby_agent.configure_sidekiq" do
      if EzlogsRubyAgent.config.instrumentation.sidekiq && sidekiq_available?
        configure_sidekiq_server
        configure_sidekiq_client
      end
    end

    # Configure job adapter detection
    initializer "ezlogs_ruby_agent.configure_jobs" do
      EzlogsRubyAgent.config.job_adapter = detect_job_adapter
    end

    # Validate configuration after Rails is fully loaded
    # :nocov:
    config.after_initialize do
      validate_configuration
    end
    # :nocov:

    private

    # Check if Sidekiq is available in the application
    #
    # @return [Boolean] True if Sidekiq is defined and available
    def sidekiq_available?
      defined?(Sidekiq)
    end

    # Configure Sidekiq server middleware
    def configure_sidekiq_server
      Sidekiq.configure_server do |config|
        config.server_middleware do |chain|
          chain.add EzlogsRubyAgent::SidekiqJobTracker
        end
      end
    rescue StandardError => e
      Rails.logger.warn "[EZLogs] Failed to configure Sidekiq server: #{e.message}" if Rails.logger
    end

    # Configure Sidekiq client middleware
    def configure_sidekiq_client
      Sidekiq.configure_client do |config|
        config.client_middleware do |chain|
          chain.add EzlogsRubyAgent::JobEnqueueMiddleware
        end
      end
    rescue StandardError => e
      Rails.logger.warn "[EZLogs] Failed to configure Sidekiq client: #{e.message}" if Rails.logger
    end

    # Detect the appropriate job adapter based on available gems
    #
    # @return [Symbol] The detected job adapter (:sidekiq, :active_job, or :none)
    def detect_job_adapter
      if sidekiq_available?
        :sidekiq
      elsif defined?(ActiveJob)
        :active_job
      else
        :none
      end
    end

    # Validate the EZLogs configuration
    def validate_configuration
      config = EzlogsRubyAgent.config

      # Validate required configuration
      if (config.service_name.nil? || config.service_name.empty?) && Rails.logger
        Rails.logger.warn "[EZLogs] service_name is not configured. Please set it in your initializer."
      end

      if (config.environment.nil? || config.environment.empty?) && Rails.logger
        Rails.logger.warn "[EZLogs] environment is not configured. Please set it in your initializer."
      end

      # Validate delivery configuration
      if (config.delivery.endpoint.nil? || config.delivery.endpoint.empty?) && Rails.logger
        Rails.logger.warn "[EZLogs] delivery endpoint is not configured. Events will not be sent."
      end

      # Log configuration summary
      if Rails.logger
        Rails.logger.info "[EZLogs] Configuration validated - Service: #{config.service_name}, Environment: #{config.environment}"
      end
    rescue StandardError => e
      Rails.logger.error "[EZLogs] Configuration validation failed: #{e.message}" if Rails.logger
    end
  end
end
