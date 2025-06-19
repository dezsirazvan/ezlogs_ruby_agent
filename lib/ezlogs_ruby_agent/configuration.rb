require 'uri'

module EzlogsRubyAgent
  # Custom exception for configuration errors
  class ConfigurationError < StandardError; end

  # Configuration validation result
  class ConfigurationValidation
    attr_reader :errors, :warnings

    def initialize
      @errors = []
      @warnings = []
    end

    def valid?
      @errors.empty?
    end

    def add_error(message)
      @errors << message
    end

    def add_warning(message)
      @warnings << message
    end
  end

  # Enhanced configuration system with elegant DSL and validation
  class Configuration
    # Legacy attributes for backward compatibility
    attr_accessor(
      :capture_http,        # Should HTTP requests be tracked?
      :capture_callbacks,   # Should AR callbacks be tracked?
      :capture_jobs,        # Should background jobs be tracked?
      :resources_to_track,  # List of resource types to track
      :exclude_resources,   # List of resource types to exclude
      :actor_extractor,     # Optional custom actor extractor Proc
      :agent_host,          # e.g. "127.0.0.1"
      :agent_port,          # e.g. 9000
      :flush_interval,      # in seconds, e.g. 1.0
      :max_buffer_size,     # e.g. 5_000
      :service_name,        # Name of the service/app
      :environment          # Environment (production, development, etc.)
    )

    # Nested configuration objects
    attr_reader :collect, :security, :performance, :delivery, :correlation

    def initialize
      # Legacy defaults
      @capture_http        = true
      @capture_callbacks   = true
      @capture_jobs        = true
      @resources_to_track  = []
      @exclude_resources   = []
      @actor_extractor     = nil
      @agent_host         = '127.0.0.1'
      @agent_port         = 9000
      @flush_interval     = 1.0
      @max_buffer_size    = 5_000
      @service_name       = nil
      @environment        = nil

      # Initialize nested configuration objects
      @collect = CollectConfiguration.new
      @security = SecurityConfiguration.new
      @performance = PerformanceConfiguration.new
      @delivery = DeliveryConfiguration.new
      @correlation = CorrelationConfiguration.new

      @frozen = false
    end

    # DSL method for collect configuration
    def collect(&block)
      return @collect unless block_given?

      raise ConfigurationError, "Configuration is frozen" if @frozen

      @collect.instance_eval(&block)
      @collect
    end

    # DSL method for security configuration
    def security(&block)
      return @security unless block_given?

      raise ConfigurationError, "Configuration is frozen" if @frozen

      @security.instance_eval(&block)
      @security
    end

    # DSL method for performance configuration
    def performance(&block)
      return @performance unless block_given?

      raise ConfigurationError, "Configuration is frozen" if @frozen

      @performance.instance_eval(&block)
      @performance
    end

    # DSL method for delivery configuration
    def delivery(&block)
      return @delivery unless block_given?

      raise ConfigurationError, "Configuration is frozen" if @frozen

      @delivery.instance_eval(&block)
      @delivery
    end

    # DSL method for correlation configuration
    def correlation(&block)
      return @correlation unless block_given?

      raise ConfigurationError, "Configuration is frozen" if @frozen

      @correlation.instance_eval(&block)
      @correlation
    end

    # Freeze configuration to prevent further modifications
    def freeze!
      @frozen = true
      @collect.freeze!
      @security.freeze!
      @performance.freeze!
      @delivery.freeze!
      @correlation.freeze!
      freeze
    end

    # Load configuration from environment variables
    def load_from_environment!
      @service_name = ENV['EZLOGS_SERVICE_NAME'] if ENV['EZLOGS_SERVICE_NAME']
      @environment = ENV['EZLOGS_ENVIRONMENT'] if ENV['EZLOGS_ENVIRONMENT']

      @performance.sample_rate = ENV['EZLOGS_SAMPLE_RATE'].to_f if ENV['EZLOGS_SAMPLE_RATE']
      @performance.buffer_size = ENV['EZLOGS_BUFFER_SIZE'].to_i if ENV['EZLOGS_BUFFER_SIZE']

      @delivery.endpoint = ENV['EZLOGS_ENDPOINT'] if ENV['EZLOGS_ENDPOINT']
      @delivery.timeout = ENV['EZLOGS_TIMEOUT'].to_i if ENV['EZLOGS_TIMEOUT']

      @security.auto_detect_pii = ENV['EZLOGS_AUTO_DETECT_PII'] != 'false'
    end

    # Validate complete configuration
    def validate!
      validation = ConfigurationValidation.new

      # Validate basic settings
      validate_basic_settings(validation)

      # Validate nested configurations
      @collect.validate!(validation)
      @security.validate!(validation)
      @performance.validate!(validation)
      @delivery.validate!(validation)
      @correlation.validate!(validation)

      unless validation.valid?
        raise ConfigurationError, "Configuration validation failed: #{validation.errors.join(', ')}"
      end

      validation
    end

    # Generate human-readable configuration summary
    def summary
      lines = []
      lines << "Service: #{@service_name || 'not set'}"
      lines << "Environment: #{@environment || 'not set'}"
      lines << "HTTP Requests: #{@collect.http_requests ? 'enabled' : 'disabled'}"
      lines << "Database Changes: #{@collect.database_changes ? 'enabled' : 'disabled'}"
      lines << "Background Jobs: #{@collect.background_jobs ? 'enabled' : 'disabled'}"
      lines << "Sample Rate: #{(@performance.sample_rate * 100).to_i}%"
      lines << "Buffer Size: #{@performance.buffer_size}"
      lines << "Delivery Endpoint: #{@delivery.endpoint || 'not set'}"
      lines << "Security: #{@security.auto_detect_pii ? 'PII detection enabled' : 'PII detection disabled'}"

      lines.join("\n")
    end

    private

    def validate_basic_settings(validation)
      validation.add_error("Service name is required") if @service_name.nil? || @service_name.empty?
      validation.add_error("Environment is required") if @environment.nil? || @environment.empty?
    end
  end

  # Collect configuration for event collection settings
  class CollectConfiguration
    attr_accessor :http_requests, :database_changes, :background_jobs, :custom_events

    def initialize
      @http_requests = true
      @database_changes = true
      @background_jobs = true
      @custom_events = true
      @frozen = false
    end

    def freeze!
      @frozen = true
      freeze
    end

    def validate!(validation)
      # No specific validation needed for collect settings
    end
  end

  # Security configuration for PII protection and sanitization
  class SecurityConfiguration
    attr_accessor :auto_detect_pii, :sanitize_fields, :max_payload_size, :custom_patterns

    def initialize
      @auto_detect_pii = true
      @sanitize_fields = []
      @max_payload_size = 64 * 1024 # 64KB
      @custom_patterns = {}
      @frozen = false
    end

    def freeze!
      @frozen = true
      freeze
    end

    def validate!(validation)
      validation.add_error("max_payload_size must be positive") if @max_payload_size <= 0
      validation.add_error("max_payload_size cannot exceed 1MB") if @max_payload_size > 1024 * 1024
    end
  end

  # Performance configuration for sampling and buffering
  class PerformanceConfiguration
    attr_accessor :sample_rate, :buffer_size, :batch_size, :flush_interval,
                  :max_concurrent_connections, :compression_enabled, :compression_threshold

    def initialize
      @sample_rate = 1.0
      @buffer_size = 10_000
      @batch_size = 1_000
      @flush_interval = 30
      @max_concurrent_connections = 5
      @compression_enabled = false
      @compression_threshold = 1024
      @frozen = false
    end

    def freeze!
      @frozen = true
      freeze
    end

    def validate!(validation)
      validation.add_error("sample_rate must be between 0.0 and 1.0") if @sample_rate < 0.0 || @sample_rate > 1.0

      if @buffer_size <= 0
        validation.add_error("buffer_size must be positive")
      elsif @buffer_size > 100_000
        validation.add_error("buffer_size cannot exceed 100,000")
      end

      if @batch_size <= 0
        validation.add_error("batch_size must be positive")
      elsif @batch_size > @buffer_size
        validation.add_error("batch_size cannot exceed buffer_size")
      end

      if @flush_interval <= 0
        validation.add_error("flush_interval must be positive")
      elsif @flush_interval > 300
        validation.add_error("flush_interval cannot exceed 5 minutes")
      end

      if @max_concurrent_connections <= 0
        validation.add_error("max_concurrent_connections must be positive")
      elsif @max_concurrent_connections > 50
        validation.add_error("max_concurrent_connections cannot exceed 50")
      end
    end
  end

  # Delivery configuration for event delivery settings
  class DeliveryConfiguration
    attr_accessor :endpoint, :timeout, :retry_attempts, :retry_backoff,
                  :circuit_breaker_threshold, :circuit_breaker_timeout, :headers

    def initialize
      @endpoint = nil
      @timeout = 30
      @retry_attempts = 3
      @retry_backoff = 2.0
      @circuit_breaker_threshold = 5
      @circuit_breaker_timeout = 60
      @headers = {}
      @frozen = false
    end

    def freeze!
      @frozen = true
      freeze
    end

    def validate!(validation)
      if @endpoint
        begin
          uri = URI.parse(@endpoint)
          validation.add_error("endpoint must use HTTP or HTTPS") unless %w[http https].include?(uri.scheme)
        rescue URI::InvalidURIError
          validation.add_error("endpoint must be a valid URL")
        end
      end

      if @timeout <= 0
        validation.add_error("timeout must be positive")
      elsif @timeout > 60
        validation.add_error("timeout cannot exceed 60 seconds")
      end

      if @retry_attempts.negative?
        validation.add_error("retry_attempts must be non-negative")
      elsif @retry_attempts > 10
        validation.add_error("retry_attempts cannot exceed 10")
      end

      validation.add_error("retry_backoff must be positive") if @retry_backoff <= 0

      validation.add_error("circuit_breaker_threshold must be positive") if @circuit_breaker_threshold <= 0

      return unless @circuit_breaker_timeout <= 0

      validation.add_error("circuit_breaker_timeout must be positive")
    end
  end

  # Correlation configuration for flow tracking
  class CorrelationConfiguration
    attr_accessor :enable_flow_tracking, :session_tracking, :user_tracking,
                  :business_process_tracking, :max_flow_depth, :flow_timeout

    def initialize
      @enable_flow_tracking = true
      @session_tracking = true
      @user_tracking = true
      @business_process_tracking = true
      @max_flow_depth = 10
      @flow_timeout = 3600 # 1 hour in seconds
      @frozen = false
    end

    def freeze!
      @frozen = true
      freeze
    end

    def validate!(validation)
      if @max_flow_depth <= 0
        validation.add_error("max_flow_depth must be positive")
      elsif @max_flow_depth > 100
        validation.add_error("max_flow_depth cannot exceed 100")
      end

      if @flow_timeout <= 0
        validation.add_error("flow_timeout must be positive")
      elsif @flow_timeout > 86_400 # 24 hours in seconds
        validation.add_error("flow_timeout cannot exceed 24 hours")
      end
    end
  end
end
