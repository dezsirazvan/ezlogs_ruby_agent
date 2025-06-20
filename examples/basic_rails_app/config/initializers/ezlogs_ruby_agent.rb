# EZLogs Ruby Agent Configuration
# This file configures event tracking for the basic Rails app example

EzlogsRubyAgent.configure do |c|
  # Required: Service identification
  c.service_name = 'basic-rails-app'
  c.environment = Rails.env

  # Enable all tracking features
  c.collect do |collect|
    collect.http_requests = true
    collect.database_changes = true
    collect.background_jobs = true
    collect.custom_events = true
  end

  # Security settings
  c.security do |security|
    security.auto_detect_pii = true
    security.sanitize_fields = %w[password token api_key]
    security.max_payload_size = 1024 * 1024 # 1MB
  end

  # Performance settings
  c.performance do |perf|
    perf.sample_rate = 1.0 # 100% sampling for demo
    perf.buffer_size = 100
    perf.flush_interval = 1.0
  end

  # Delivery settings (for demo, we'll use debug mode)
  c.delivery do |delivery|
    delivery.endpoint = nil # Disable actual delivery for demo
  end

  # Correlation settings
  c.correlation do |correlation|
    correlation.enable_flow_tracking = true
    correlation.max_flow_depth = 10
  end

  # Actor extraction
  c.actor_extractor = lambda { |context|
    context.current_user&.id || context.request&.remote_ip
  }
end

# Enable debug mode in development
EzlogsRubyAgent.debug_mode = true if Rails.env.development?

# Enable test mode in test environment
if Rails.env.test?
  EzlogsRubyAgent.test_mode do
    # All events captured in memory for testing
  end
end
