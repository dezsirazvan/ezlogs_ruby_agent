# Configuration Guide

EZLogs Ruby Agent provides a powerful and flexible configuration system that adapts to your application's needs. This guide covers all configuration options from basic setup to advanced tuning.

## 🚀 Basic Configuration

### Minimal Setup

The absolute minimum configuration requires just two settings:

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |c|
  c.service_name = 'my-awesome-app'
  c.environment = Rails.env
end
```

This enables:
- HTTP request tracking
- Database change tracking
- Background job tracking
- Default security settings
- Optimal performance settings

### Standard Configuration

A typical production configuration:

```ruby
EzlogsRubyAgent.configure do |c|
  # Required: Service identification
  c.service_name = 'my-awesome-app'
  c.environment = Rails.env
  
  # Optional: Customize collection
  c.collect do |collect|
    collect.http_requests = true
    collect.database_changes = true
    collect.background_jobs = true
    collect.custom_events = true
  end
  
  # Optional: Security settings
  c.security do |security|
    security.auto_detect_pii = true
    security.sanitize_fields = ['password', 'token', 'api_key']
    security.max_payload_size = 1024 * 1024  # 1MB
  end
  
  # Optional: Performance tuning
  c.performance do |perf|
    perf.sample_rate = 1.0
    perf.buffer_size = 1000
    perf.flush_interval = 1.0
    perf.max_concurrent_connections = 5
  end
  
  # Optional: Delivery settings
  c.delivery do |delivery|
    delivery.endpoint = 'https://api.ezlogs.com/v1/events'
    delivery.timeout = 30
    delivery.retry_attempts = 3
  end
  
  # Optional: Correlation settings
  c.correlation do |correlation|
    correlation.enable_flow_tracking = true
    correlation.max_flow_depth = 10
  end
end
```

## 📊 Collection Configuration

Control what events are captured and how they're processed.

### HTTP Request Tracking

```ruby
c.collect do |collect|
  collect.http_requests = true
  
  # Optional: Filter specific paths
  collect.http_paths_to_track = ['/api/*', '/admin/*']
  collect.http_paths_to_exclude = ['/health', '/metrics']
  
  # Optional: Filter by HTTP methods
  collect.http_methods_to_track = ['GET', 'POST', 'PUT', 'DELETE']
  
  # Optional: Capture request/response bodies (use with caution)
  collect.capture_request_body = false
  collect.capture_response_body = false
  collect.max_body_size = 1024  # bytes
end
```

### Database Change Tracking

```ruby
c.collect do |collect|
  collect.database_changes = true
  
  # Optional: Track specific models
  collect.resources_to_track = ['User', 'Order', 'Payment']
  collect.exclude_resources = ['Admin', 'AuditLog', 'Session']
  
  # Optional: Track specific operations
  collect.track_creates = true
  collect.track_updates = true
  collect.track_destroys = true
  
  # Optional: Capture field changes
  collect.capture_changes = true
  collect.exclude_changes = ['updated_at', 'created_at']
end
```

### Background Job Tracking

```ruby
c.collect do |collect|
  collect.background_jobs = true
  
  # Optional: Track specific job classes
  collect.jobs_to_track = ['ProcessOrderJob', 'SendEmailJob']
  collect.exclude_jobs = ['CleanupJob', 'MaintenanceJob']
  
  # Optional: Track job arguments (use with caution)
  collect.capture_job_arguments = false
  collect.max_argument_size = 512  # bytes
end
```

### Custom Event Tracking

```ruby
c.collect do |collect|
  collect.custom_events = true
  
  # Optional: Validate event structure
  collect.validate_events = true
  
  # Optional: Required event fields
  collect.required_event_fields = ['event_type', 'action']
end
```

## 🛡️ Security Configuration

Protect sensitive data and ensure compliance.

### PII Detection & Sanitization

```ruby
c.security do |security|
  # Enable automatic PII detection
  security.auto_detect_pii = true
  
  # Manually specify fields to sanitize
  security.sanitize_fields = [
    'password',
    'token',
    'api_key',
    'ssn',
    'credit_card',
    'email'
  ]
  
  # Custom regex patterns for sensitive data
  security.custom_patterns = {
    'api_key' => /\b[A-Za-z0-9]{32}\b/,
    'phone' => /\b\d{3}-\d{3}-\d{4}\b/,
    'credit_card' => /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/
  }
  
  # Sanitization method
  security.sanitization_method = :mask  # :mask, :remove, :hash
  security.mask_character = '*'  # Character to use for masking
end
```

### Payload Limits

```ruby
c.security do |security|
  # Maximum payload size
  security.max_payload_size = 1024 * 1024  # 1MB
  
  # Maximum field value size
  security.max_field_size = 1024  # 1KB
  
  # Maximum number of fields per event
  security.max_fields_per_event = 100
end
```

### Field Filtering

```ruby
c.security do |security|
  # Fields to always exclude
  security.exclude_fields = [
    'password',
    'secret',
    'private_key',
    'session_data'
  ]
  
  # Fields to only include (whitelist)
  security.include_only_fields = [
    'id',
    'name',
    'email',
    'status'
  ]
  
  # Nested field filtering
  security.exclude_nested_fields = [
    'user.password',
    'order.payment.token',
    'config.secrets'
  ]
end
```

## ⚡ Performance Configuration

Optimize for your application's performance requirements.

### Sampling & Buffering

```ruby
c.performance do |perf|
  # Event sampling rate (0.0 to 1.0)
  perf.sample_rate = 1.0  # 100% of events
  
  # Buffer size for batching
  perf.buffer_size = 1000
  
  # Flush interval in seconds
  perf.flush_interval = 1.0
  
  # Maximum events per batch
  perf.max_batch_size = 100
end
```

### Connection Management

```ruby
c.performance do |perf|
  # Connection pool size
  perf.connection_pool_size = 5
  
  # Connection timeout
  perf.connection_timeout = 30
  
  # Keep-alive settings
  perf.keep_alive = true
  perf.keep_alive_timeout = 60
end
```

### Memory Management

```ruby
c.performance do |perf|
  # Maximum memory usage
  perf.max_memory_usage = 100 * 1024 * 1024  # 100MB
  
  # Garbage collection frequency
  perf.gc_frequency = 1000  # events
  
  # Event cleanup interval
  perf.cleanup_interval = 60  # seconds
end
```

### Threading

```ruby
c.performance do |perf|
  # Background thread count
  perf.background_threads = 2
  
  # Thread priority
  perf.thread_priority = :low
  
  # Thread timeout
  perf.thread_timeout = 30
end
```

## 🚚 Delivery Configuration

Configure how events are delivered to your analytics platform.

### Endpoint Configuration

```ruby
c.delivery do |delivery|
  # Delivery endpoint
  delivery.endpoint = 'https://api.ezlogs.com/v1/events'
  
  # API key (from environment variable)
  delivery.api_key = ENV['EZLOGS_API_KEY']
  
  # Request timeout
  delivery.timeout = 30
  
  # Retry configuration
  delivery.retry_attempts = 3
  delivery.retry_backoff = 1.5
  delivery.retry_max_delay = 60
end
```

### Authentication

```ruby
c.delivery do |delivery|
  # Basic authentication
  delivery.username = ENV['EZLOGS_USERNAME']
  delivery.password = ENV['EZLOGS_PASSWORD']
  
  # Bearer token
  delivery.bearer_token = ENV['EZLOGS_BEARER_TOKEN']
  
  # Custom headers
  delivery.custom_headers = {
    'X-Custom-Header' => 'value',
    'User-Agent' => 'EZLogs-Ruby-Agent/1.0'
  }
end
```

### Compression & Encoding

```ruby
c.delivery do |delivery|
  # Enable compression
  delivery.compress_payloads = true
  delivery.compression_level = 6
  
  # Encoding
  delivery.encoding = 'gzip'  # gzip, deflate, none
  
  # Batch delivery
  delivery.batch_delivery = true
  delivery.max_batch_size = 100
  delivery.batch_timeout = 5
end
```

## 🔗 Correlation Configuration

Configure request tracing and business process tracking.

### Flow Tracking

```ruby
c.correlation do |correlation|
  # Enable business flow tracking
  correlation.enable_flow_tracking = true
  
  # Maximum flow depth
  correlation.max_flow_depth = 10
  
  # Flow timeout
  correlation.flow_timeout = 3600  # 1 hour
  
  # Auto-generate correlation IDs
  correlation.auto_correlation_ids = true
end
```

### Request Tracing

```ruby
c.correlation do |correlation|
  # Enable request tracing
  correlation.enable_request_tracing = true
  
  # Trace header names
  correlation.trace_header = 'X-Trace-ID'
  correlation.span_header = 'X-Span-ID'
  
  # Propagate headers
  correlation.propagate_headers = true
end
```

### Context Management

```ruby
c.correlation do |correlation|
  # Context storage
  correlation.context_storage = :thread_local  # :thread_local, :fiber_local
  
  # Context cleanup
  correlation.auto_cleanup = true
  correlation.cleanup_interval = 300  # 5 minutes
  
  # Context serialization
  correlation.serializable_context = true
end
```

## 🎭 Actor Extraction

Configure how to identify who performed each action.

### Basic Actor Extraction

```ruby
# Extract user ID from current_user
c.actor_extractor = ->(context) do
  context.current_user&.id
end
```

### Advanced Actor Extraction

```ruby
c.actor_extractor = ->(context) do
  # Try multiple sources
  actor = context.current_user&.id ||
          context.request&.session[:user_id] ||
          context.request&.headers['X-User-ID'] ||
          context.request&.remote_ip
  
  # Add context
  {
    id: actor,
    type: context.current_user ? 'user' : 'anonymous',
    session_id: context.request&.session[:session_id]
  }
end
```

### Custom Actor Context

```ruby
c.actor_extractor = ->(context) do
  user = context.current_user
  
  return nil unless user
  
  {
    id: user.id,
    email: user.email,
    role: user.role,
    organization_id: user.organization_id,
    permissions: user.permissions
  }
end
```

## 🌍 Environment-Specific Configuration

### Development Environment

```ruby
# config/environments/development.rb
EzlogsRubyAgent.configure do |c|
  c.service_name = 'my-app-dev'
  c.environment = 'development'
  
  # Enable debug mode
  EzlogsRubyAgent.debug_mode = true
  
  # Lower sampling for development
  c.performance do |perf|
    perf.sample_rate = 0.1  # 10% sampling
    perf.buffer_size = 100
  end
  
  # More verbose logging
  c.delivery do |delivery|
    delivery.endpoint = 'http://localhost:9000/events'
  end
end
```

### Test Environment

```ruby
# config/environments/test.rb
EzlogsRubyAgent.configure do |c|
  c.service_name = 'my-app-test'
  c.environment = 'test'
  
  # Disable actual delivery in tests
  c.delivery do |delivery|
    delivery.endpoint = nil
  end
  
  # Enable test mode
  EzlogsRubyAgent.test_mode do
    # Events captured in memory
  end
end
```

### Production Environment

```ruby
# config/environments/production.rb
EzlogsRubyAgent.configure do |c|
  c.service_name = 'my-app-prod'
  c.environment = 'production'
  
  # Load from environment variables
  c.load_from_environment!
  
  # High-performance settings
  c.performance do |perf|
    perf.sample_rate = 0.1  # 10% sampling for high traffic
    perf.buffer_size = 5000
    perf.flush_interval = 2.0
  end
  
  # Strict security
  c.security do |security|
    security.auto_detect_pii = true
    security.sanitize_fields = ['password', 'token', 'secret']
    security.max_payload_size = 512 * 1024  # 512KB
  end
end
```

## 🔧 Environment Variables

Configure via environment variables for containerized deployments:

```bash
# Required
export EZLOGS_SERVICE_NAME="my-awesome-app"
export EZLOGS_ENVIRONMENT="production"

# Collection
export EZLOGS_SAMPLE_RATE="0.1"
export EZLOGS_BUFFER_SIZE="5000"

# Security
export EZLOGS_AUTO_DETECT_PII="true"
export EZLOGS_MAX_PAYLOAD_SIZE="524288"

# Delivery
export EZLOGS_ENDPOINT="https://api.ezlogs.com/v1/events"
export EZLOGS_API_KEY="your-api-key"
export EZLOGS_TIMEOUT="30"

# Performance
export EZLOGS_FLUSH_INTERVAL="2.0"
export EZLOGS_MAX_CONCURRENT_CONNECTIONS="10"
```

Load environment variables in configuration:

```ruby
EzlogsRubyAgent.configure do |c|
  c.load_from_environment!
  
  # Override specific settings
  c.service_name = 'my-app' if Rails.env.development?
end
```

## ✅ Configuration Validation

Validate your configuration to catch issues early:

```ruby
EzlogsRubyAgent.configure do |c|
  # ... your configuration ...
  
  # Validate configuration
  validation = c.validate!
  
  if validation.valid?
    puts "✅ Configuration is valid"
    puts validation.summary
  else
    puts "❌ Configuration errors:"
    validation.errors.each { |error| puts "  - #{error}" }
    raise EzlogsRubyAgent::ConfigurationError, "Invalid configuration"
  end
end
```

## 📊 Configuration Summary

Generate a human-readable summary of your configuration:

```ruby
config = EzlogsRubyAgent.config
puts config.summary
```

Output example:
```
Service: my-awesome-app
Environment: production
HTTP Requests: enabled
Database Changes: enabled
Background Jobs: enabled
Sample Rate: 10%
Buffer Size: 5000
Delivery Endpoint: https://api.ezlogs.com/v1/events
Security: PII detection enabled
```

## 🔄 Dynamic Configuration

Update configuration at runtime (use with caution):

```ruby
# Update sampling rate based on load
if high_traffic?
  EzlogsRubyAgent.config.performance.sample_rate = 0.05  # 5%
else
  EzlogsRubyAgent.config.performance.sample_rate = 1.0   # 100%
end

# Update security settings
EzlogsRubyAgent.config.security.sanitize_fields << 'new_sensitive_field'
```

## 🚨 Configuration Best Practices

### Security
- Always enable PII detection in production
- Sanitize sensitive fields
- Set appropriate payload size limits
- Use environment variables for secrets

### Performance
- Use sampling for high-traffic applications
- Tune buffer sizes based on memory constraints
- Monitor delivery performance
- Set appropriate timeouts

### Reliability
- Configure retry logic for network failures
- Set up health monitoring
- Use circuit breakers for external dependencies
- Implement graceful degradation

### Development
- Enable debug mode in development
- Use test mode in test suites
- Validate configuration early
- Document custom settings

## 📚 Next Steps

- **[Performance Guide](performance.md)** - Optimization and tuning
- **[Security Guide](security.md)** - Security best practices
- **[API Reference](../lib/ezlogs_ruby_agent.rb)** - Complete API documentation
- **[Examples](../examples/)** - Complete example applications

---

**Your configuration is the foundation of successful event tracking.** Take time to tune it for your specific needs and requirements! 🚀 