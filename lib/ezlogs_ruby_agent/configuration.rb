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
    attr_accessor :service_name, :environment, :instrumentation, :security, :job_adapter, :included_resources,
                  :excluded_resources, :performance, :delivery, :correlation, :actor_extractor

    def initialize
      # Core settings with smart defaults
      @service_name = detect_service_name
      @environment = detect_environment

      # Actor extraction - can be customized by users
      @actor_extractor = nil

      # Instrumentation settings - all enabled by default for zero-config
      @instrumentation = OpenStruct.new(
        http: true,
        active_record: true,
        active_job: true,
        sidekiq: true,
        custom: true
      )

      # Security settings with comprehensive defaults
      @security = OpenStruct.new(
        auto_detect_pii: true,
        sensitive_fields: %w[password token api_key secret key authorization bearer],
        custom_pii_patterns: {},
        max_event_size: 1024 * 1024, # 1MB
        redacted_headers: %w[authorization x-api-key x-auth-token],
        redacted_cookies: %w[session _csrf_token]
      )

      # Performance settings optimized for production
      @performance = OpenStruct.new(
        sample_rate: 1.0,
        event_buffer_size: 1000,
        max_delivery_connections: 10,
        enable_compression: true,
        enable_async: true
      )

      # Delivery settings with sensible defaults
      @delivery = OpenStruct.new(
        endpoint: nil,
        timeout: 30,
        retry_attempts: 3,
        retry_backoff: 1.0,
        batch_size: 100,
        flush_interval: 5.0,
        headers: {},
        circuit_breaker_threshold: 5,
        circuit_breaker_timeout: 60
      )

      # Correlation settings for flow tracking
      @correlation = OpenStruct.new(
        enable_correlation: true,
        max_correlation_depth: 10,
        thread_safe: true,
        auto_generate_correlation_ids: true
      )

      # Resource tracking
      @included_resources = []
      @excluded_resources = []

      # Job adapter detection
      @job_adapter = detect_job_adapter

      @frozen = false
    end

    # Smart service name detection
    def detect_service_name
      return ENV['EZLOGS_SERVICE_NAME'] if ENV['EZLOGS_SERVICE_NAME']
      return Rails.application.class.module_parent_name.underscore if defined?(Rails)
      return File.basename(Dir.pwd) if Dir.pwd != '/'

      'unknown-service'
    end

    # Smart environment detection
    def detect_environment
      return ENV['EZLOGS_ENVIRONMENT'] if ENV['EZLOGS_ENVIRONMENT']
      return Rails.env if defined?(Rails) && Rails.respond_to?(:env)
      return ENV['RAILS_ENV'] if ENV['RAILS_ENV']
      return ENV['RACK_ENV'] if ENV['RACK_ENV']

      'development'
    end

    # Smart job adapter detection
    def detect_job_adapter
      return :sidekiq if defined?(Sidekiq)
      return :active_job if defined?(ActiveJob)

      :active_job # fallback
    end

    # Backward compatibility methods (deprecated)
    def collect(&block)
      warn '[EZLogs] config.collect is deprecated. Use config.instrumentation instead.'
      return @instrumentation unless block_given?
      raise ConfigurationError, "Configuration is frozen" if @frozen

      @instrumentation.instance_eval(&block)
      @instrumentation
    end

    # DSL method for instrumentation configuration
    def instrumentation(&block)
      return @instrumentation unless block_given?
      raise ConfigurationError, "Configuration is frozen" if @frozen

      @instrumentation.instance_eval(&block)
      @instrumentation
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

    # Convenience method for quick setup
    def quick_setup(service_name: nil, environment: nil)
      @service_name = service_name if service_name
      @environment = environment if environment
      self
    end

    # Freeze configuration to prevent further modifications
    def freeze!
      @frozen = true
      @instrumentation.freeze!
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

      # Performance settings
      @performance.sample_rate = ENV['EZLOGS_SAMPLE_RATE'].to_f if ENV['EZLOGS_SAMPLE_RATE']
      @performance.event_buffer_size = ENV['EZLOGS_EVENT_BUFFER_SIZE'].to_i if ENV['EZLOGS_EVENT_BUFFER_SIZE']
      if ENV['EZLOGS_MAX_DELIVERY_CONNECTIONS']
        @performance.max_delivery_connections = ENV['EZLOGS_MAX_DELIVERY_CONNECTIONS'].to_i
      end

      # Delivery settings
      @delivery.endpoint = ENV['EZLOGS_ENDPOINT'] if ENV['EZLOGS_ENDPOINT']
      @delivery.timeout = ENV['EZLOGS_TIMEOUT'].to_i if ENV['EZLOGS_TIMEOUT']
      @delivery.flush_interval = ENV['EZLOGS_FLUSH_INTERVAL'].to_f if ENV['EZLOGS_FLUSH_INTERVAL']
      @delivery.headers = JSON.parse(ENV['EZLOGS_DELIVERY_HEADERS']) if ENV['EZLOGS_DELIVERY_HEADERS']
      if ENV['EZLOGS_CIRCUIT_BREAKER_THRESHOLD']
        @delivery.circuit_breaker_threshold = ENV['EZLOGS_CIRCUIT_BREAKER_THRESHOLD'].to_i
      end
      if ENV['EZLOGS_CIRCUIT_BREAKER_TIMEOUT']
        @delivery.circuit_breaker_timeout = ENV['EZLOGS_CIRCUIT_BREAKER_TIMEOUT'].to_i
      end

      # Security settings
      @security.auto_detect_pii = ENV['EZLOGS_AUTO_DETECT_PII'] != 'false'
      @security.max_event_size = ENV['EZLOGS_MAX_EVENT_SIZE'].to_i if ENV['EZLOGS_MAX_EVENT_SIZE']

      # Instrumentation settings
      @instrumentation.http = ENV['EZLOGS_HTTP'] != 'false'
      @instrumentation.active_record = ENV['EZLOGS_ACTIVE_RECORD'] != 'false'
      @instrumentation.active_job = ENV['EZLOGS_ACTIVE_JOB'] != 'false'
      @instrumentation.sidekiq = ENV['EZLOGS_SIDEKIQ'] != 'false'
    end

    # Validate complete configuration
    def validate!
      validation = ConfigurationValidation.new
      validate_basic_settings(validation)
      validate_instrumentation_settings(validation)
      validate_security_settings(validation)
      validate_performance_settings(validation)
      validate_delivery_settings(validation)
      validate_correlation_settings(validation)
      unless validation.valid?
        raise ConfigurationError, "Configuration validation failed: #{validation.errors.join(', ')}"
      end

      validation
    end

    # Generate human-readable configuration summary
    def summary
      lines = []
      lines << "=== EZLogs Configuration Summary ==="
      lines << "Service: #{@service_name || 'not set'}"
      lines << "Environment: #{@environment || 'not set'}"
      lines << ""
      lines << "Instrumentation Settings:"
      lines << "  HTTP: #{@instrumentation.http ? '✓ enabled' : '✗ disabled'}"
      lines << "  ActiveRecord: #{@instrumentation.active_record ? '✓ enabled' : '✗ disabled'}"
      lines << "  ActiveJob: #{@instrumentation.active_job ? '✓ enabled' : '✗ disabled'}"
      lines << "  Sidekiq: #{@instrumentation.sidekiq ? '✓ enabled' : '✗ disabled'}"
      lines << "  Custom: #{@instrumentation.custom ? '✓ enabled' : '✗ disabled'}"
      lines << ""
      lines << "Performance Settings:"
      lines << "  Sample Rate: #{(@performance.sample_rate * 100).to_i}%"
      lines << "  Event Buffer Size: #{@performance.event_buffer_size}"
      lines << "  Max Delivery Connections: #{@performance.max_delivery_connections}"
      lines << "  Async: #{@performance.enable_async ? '✓ enabled' : '✗ disabled'}"
      lines << "  Compression: #{@performance.enable_compression ? '✓ enabled' : '✗ disabled'}"
      lines << ""
      lines << "Security Settings:"
      lines << "  PII Detection: #{@security.auto_detect_pii ? '✓ enabled' : '✗ disabled'}"
      lines << "  Sensitive Fields: #{@security.sensitive_fields.join(', ')}"
      lines << "  Max Event Size: #{@security.max_event_size} bytes"
      lines << ""
      lines << "Delivery Settings:"
      lines << "  Endpoint: #{@delivery.endpoint || 'not configured'}"
      lines << "  Timeout: #{@delivery.timeout}s"
      lines << "  Flush Interval: #{@delivery.flush_interval}s"
      lines << "  Batch Size: #{@delivery.batch_size}"
      lines << "  Circuit Breaker Threshold: #{@delivery.circuit_breaker_threshold}"
      lines << "  Circuit Breaker Timeout: #{@delivery.circuit_breaker_timeout}s"
      lines << ""
      lines << "Correlation Settings:"
      lines << "  Correlation Enabled: #{@correlation.enable_correlation ? '✓ enabled' : '✗ disabled'}"
      lines << "  Max Correlation Depth: #{@correlation.max_correlation_depth}"
      lines << "  Thread Safe: #{@correlation.thread_safe ? '✓ enabled' : '✗ disabled'}"
      lines << "  Auto Generate IDs: #{@correlation.auto_generate_correlation_ids ? '✓ enabled' : '✗ disabled'}"
      lines << ""
      lines << "Included Resources: #{@included_resources.inspect}"
      lines << "Excluded Resources: #{@excluded_resources.inspect}"
      lines.join("\n")
    end

    private

    def validate_basic_settings(validation)
      validation.add_error("Service name is required") if @service_name.nil? || @service_name.empty?
      validation.add_error("Environment is required") if @environment.nil? || @environment.empty?
    end

    def validate_instrumentation_settings(validation)
      # All instrumentation settings are optional and have sensible defaults
    end

    def validate_security_settings(validation)
      validation.add_error("max_event_size must be positive") if @security.max_event_size <= 0
      validation.add_error("max_event_size cannot exceed 10MB") if @security.max_event_size > 10 * 1024 * 1024
    end

    def validate_performance_settings(validation)
      if @performance.sample_rate < 0.0 || @performance.sample_rate > 1.0
        validation.add_error("sample_rate must be between 0.0 and 1.0")
      end
      validation.add_error("event_buffer_size must be positive") if @performance.event_buffer_size <= 0
      validation.add_error("max_delivery_connections must be positive") if @performance.max_delivery_connections <= 0
    end

    def validate_delivery_settings(validation)
      if @delivery.endpoint
        begin
          uri = URI.parse(@delivery.endpoint)
          validation.add_error("endpoint must be a valid URL") unless %w[http https].include?(uri.scheme)
        rescue URI::InvalidURIError
          validation.add_error("endpoint must be a valid URL")
        end
      end
      validation.add_error("timeout must be positive") if @delivery.timeout <= 0
      validation.add_error("timeout cannot exceed 60 seconds") if @delivery.timeout > 60
      validation.add_error("flush_interval must be positive") if @delivery.flush_interval <= 0
      validation.add_error("batch_size must be positive") if @delivery.batch_size <= 0
    end

    def validate_correlation_settings(validation)
      validation.add_error("max_correlation_depth must be positive") if @correlation.max_correlation_depth <= 0
      validation.add_error("max_correlation_depth cannot exceed 50") if @correlation.max_correlation_depth > 50
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
    attr_accessor :auto_detect_pii, :sensitive_fields, :max_event_size, :custom_pii_patterns

    def initialize
      @auto_detect_pii = true
      @sensitive_fields = []
      @max_event_size = 64 * 1024 # 64KB
      @custom_pii_patterns = {}
      @frozen = false
    end

    def freeze!
      @frozen = true
      freeze
    end

    def validate!(validation)
      validation.add_error("max_event_size must be positive") if @max_event_size <= 0
      validation.add_error("max_event_size cannot exceed 1MB") if @max_event_size > 1024 * 1024
    end
  end

  # Performance configuration for optimization settings
  class PerformanceConfiguration
    attr_accessor :sample_rate, :event_buffer_size, :max_delivery_connections,
                  :enable_compression, :enable_async

    def initialize
      @sample_rate = 1.0
      @event_buffer_size = 1000
      @max_delivery_connections = 10
      @enable_compression = true
      @enable_async = true
      @frozen = false
    end

    def freeze!
      @frozen = true
      freeze
    end

    def validate!(validation)
      validation.add_error("sample_rate must be between 0.0 and 1.0") if @sample_rate < 0.0 || @sample_rate > 1.0
      validation.add_error("event_buffer_size must be positive") if @event_buffer_size <= 0
      validation.add_error("max_delivery_connections must be positive") if @max_delivery_connections <= 0
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
          validation.add_error("endpoint must be a valid URL") unless %w[http https].include?(uri.scheme)
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
    attr_accessor :enable_correlation, :session_tracking, :user_tracking,
                  :business_process_tracking, :max_correlation_depth, :flow_timeout

    def initialize
      @enable_correlation = true
      @session_tracking = true
      @user_tracking = true
      @business_process_tracking = true
      @max_correlation_depth = 10
      @flow_timeout = 3600 # 1 hour in seconds
      @frozen = false
    end

    def freeze!
      @frozen = true
      freeze
    end

    def validate!(validation)
      if @max_correlation_depth <= 0
        validation.add_error("max_correlation_depth must be positive")
      elsif @max_correlation_depth > 100
        validation.add_error("max_correlation_depth cannot exceed 100")
      end

      if @flow_timeout <= 0
        validation.add_error("flow_timeout must be positive")
      elsif @flow_timeout > 86_400 # 24 hours in seconds
        validation.add_error("flow_timeout cannot exceed 24 hours")
      end
    end
  end
end
