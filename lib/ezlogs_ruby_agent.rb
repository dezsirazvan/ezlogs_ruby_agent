require 'ezlogs_ruby_agent/railtie' if defined?(Rails)
require 'ezlogs_ruby_agent/configuration'
require 'ezlogs_ruby_agent/universal_event'
require 'ezlogs_ruby_agent/event_processor'
require 'ezlogs_ruby_agent/delivery_engine'
require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/correlation_manager'
require 'ezlogs_ruby_agent/event_pool'
require 'ezlogs_ruby_agent/debug_tools'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/http_tracker'
require 'ezlogs_ruby_agent/callbacks_tracker'
require 'ezlogs_ruby_agent/job_tracker'
require 'ezlogs_ruby_agent/sidekiq_job_tracker'
require 'ezlogs_ruby_agent/job_enqueue_middleware'

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

  # Debug mode accessors
  def self.debug_mode
    DebugTools.debug_mode
  end

  def self.debug_mode=(enabled)
    if enabled
      DebugTools.enable_debug_mode
    else
      DebugTools.disable_debug_mode
    end
  end

  # Test mode for capturing events
  def self.test_mode(&block)
    DebugTools.test_mode(&block)
  end

  # Get captured events for testing
  def self.captured_events
    DebugTools.captured_events
  end

  # Clear captured events
  def self.clear_captured_events
    DebugTools.clear_captured_events
  end

  # Performance monitoring
  def self.performance_monitor
    @performance_monitor ||= PerformanceMonitor.new
  end

  # Health status for all components
  def self.health_status
    {
      writer: writer.health_status,
      delivery_engine: delivery_engine.health_status,
      correlation_manager: {
        current_context: CorrelationManager.current_context&.to_h,
        pool_stats: EventPool.pool_stats
      },
      performance: performance_monitor.metrics,
      debug_mode: debug_mode,
      config: {
        service_name: config.service_name,
        environment: config.environment,
        endpoint: config.delivery.endpoint
      }
    }
  end

  # Log custom event with correlation inheritance
  def self.log_event(event_type:, action:, actor:, subject: nil, metadata: nil, timestamp: nil)
    event = UniversalEvent.new(
      event_type: event_type,
      action: action,
      actor: actor,
      subject: subject,
      metadata: metadata,
      timestamp: timestamp
    )

    # Log the event (EventWriter will handle debug capture of processed event)
    writer.log(event)
  rescue StandardError => e
    warn "[Ezlogs] Failed to log event: #{e.class}: #{e.message}"
  end

  # Start a correlation flow for business processes
  def self.start_flow(flow_type, entity_id, metadata = {})
    CorrelationManager.start_flow_context(flow_type, entity_id, metadata)
  end

  # Get current correlation context
  def self.current_correlation_context
    CorrelationManager.current_context
  end

  # Extract correlation data for async operations
  def self.extract_correlation_data
    CorrelationManager.extract_correlation_data
  end

  # Restore correlation context from serialized data
  def self.restore_correlation_context(correlation_data)
    CorrelationManager.restore_context(correlation_data)
  end

  # Clear current correlation context
  def self.clear_correlation_context
    CorrelationManager.clear_context
  end

  # Performance timing helpers
  def self.timing(name, &block)
    performance_monitor.start_timing(name)
    result = block.call
    performance_monitor.end_timing(name)
    result
  end

  def self.record_metric(name, value, tags = {})
    performance_monitor.increment_counter(name, value)
    DebugTools.record_metric(name, value, tags) if debug_mode
  end

  # Shutdown all components gracefully
  def self.shutdown
    delivery_engine.shutdown
    EventPool.clear_pool
    DebugTools.disable_debug_mode
  end
end