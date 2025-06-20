# Configuration Guide

EZLogs Ruby Agent is designed to work out of the box with intelligent defaults, but you can customize every aspect of its behavior.

## 🚀 Zero-Config Setup

EZLogs Ruby Agent works immediately with intelligent defaults:

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |config|
  # That's it! All collectors enabled by default
  # Service name and environment auto-detected
end
```

**Default Behavior:**
- ✅ **Service Name**: Auto-detected from Rails app name or directory
- ✅ **Environment**: Auto-detected from `Rails.env` or environment variables
- ✅ **All Collectors**: HTTP, Database, Jobs, Sidekiq enabled
- ✅ **Security**: PII detection and sanitization enabled
- ✅ **Performance**: Optimized for production workloads

## 🔧 Basic Configuration

### Core Settings

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |config|
  # Core settings
  config.service_name = 'my-awesome-app'
  config.environment = Rails.env
  
  # Delivery settings (where events are sent)
  config.delivery do |delivery|
    delivery.endpoint = 'https://logs.your-domain.com/events'
    delivery.timeout = 30
    delivery.flush_interval = 5.0
  end
end
```

### Environment Variables

```bash
# Core settings
export EZLOGS_SERVICE_NAME="my-app"
export EZLOGS_ENVIRONMENT="production"

# Delivery settings
export EZLOGS_ENDPOINT="https://logs.your-domain.com/events"
export EZLOGS_API_KEY="your-api-key"
```

## 📊 Instrumentation Settings

Control what gets tracked automatically:

```ruby
EzlogsRubyAgent.configure do |config|
  config.instrumentation do |inst|
    inst.http = true              # HTTP request tracking
    inst.active_record = true     # Database change tracking
    inst.active_job = true        # ActiveJob tracking
    inst.sidekiq = true           # Sidekiq job tracking
    inst.custom = true            # Custom event tracking
  end
end
```

### Disable Specific Collectors

```ruby
# Disable database tracking in development
if Rails.env.development?
  config.instrumentation.active_record = false
end

# Disable Sidekiq if not using it
unless defined?(Sidekiq)
  config.instrumentation.sidekiq = false
end
```

## 🔒 Security Settings

### PII Protection

```ruby
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    security.auto_detect_pii = true
    security.sensitive_fields = ['password', 'token', 'api_key', 'ssn']
    security.max_event_size = 1024 * 1024 # 1MB
    security.custom_pii_patterns = {
      'employee_id' => /\bEMP-\d{6}\b/,
      'credit_card' => /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/
    }
  end
end
```

### Field Filtering

```ruby
# Include only specific resources
config.included_resources = ['order', 'user', 'payment']

# Exclude sensitive resources
config.excluded_resources = ['temp', 'cache', 'session', 'password_reset']
```

### Environment Variables

```bash
# Security settings
export EZLOGS_AUTO_DETECT_PII="true"
export EZLOGS_MAX_EVENT_SIZE="1048576"
export EZLOGS_SENSITIVE_FIELDS="password,token,api_key,ssn"
```

## ⚡ Performance Settings

### Optimization

```ruby
EzlogsRubyAgent.configure do |config|
  config.performance do |perf|
    perf.sample_rate = 1.0        # 100% sampling
    perf.event_buffer_size = 1000
    perf.max_delivery_connections = 10
    perf.enable_compression = true
    perf.enable_async = true
  end
end
```

### High-Traffic Applications

```ruby
# For high-traffic apps, reduce sampling
config.performance.sample_rate = 0.1  # 10% sampling

# Increase buffer size for batch processing
config.performance.event_buffer_size = 5000

# More delivery connections
config.performance.max_delivery_connections = 20
```

### Environment Variables

```bash
# Performance settings
export EZLOGS_SAMPLE_RATE="1.0"
export EZLOGS_EVENT_BUFFER_SIZE="1000"
export EZLOGS_MAX_DELIVERY_CONNECTIONS="10"
export EZLOGS_ENABLE_COMPRESSION="true"
```

## 🌐 Delivery Settings

### Go Server Configuration

```ruby
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    delivery.endpoint = 'https://logs.your-domain.com/events'
    delivery.timeout = 30
    delivery.flush_interval = 5.0
    delivery.batch_size = 100
    delivery.retry_attempts = 3
    delivery.retry_backoff = 2.0
    delivery.circuit_breaker_threshold = 5
    delivery.circuit_breaker_timeout = 60
    delivery.headers = {
      'X-API-Key' => ENV['EZLOGS_API_KEY'],
      'X-Service-Name' => 'my-app'
    }
  end
end
```

### Production Delivery Settings

```ruby
# Production-optimized delivery
config.delivery do |delivery|
  delivery.endpoint = 'https://logs.your-domain.com/events'
  delivery.timeout = 30
  delivery.flush_interval = 2.0        # Faster flushing
  delivery.batch_size = 200            # Larger batches
  delivery.retry_attempts = 5          # More retries
  delivery.retry_backoff = 1.5         # Faster backoff
  delivery.circuit_breaker_threshold = 10
  delivery.circuit_breaker_timeout = 120
  delivery.headers = {
    'X-API-Key' => ENV['EZLOGS_API_KEY'],
    'X-Environment' => Rails.env,
    'X-Version' => '1.0.0'
  }
end
```

### Environment Variables

```bash
# Delivery settings
export EZLOGS_ENDPOINT="https://logs.your-domain.com/events"
export EZLOGS_TIMEOUT="30"
export EZLOGS_FLUSH_INTERVAL="5.0"
export EZLOGS_BATCH_SIZE="100"
export EZLOGS_RETRY_ATTEMPTS="3"
export EZLOGS_API_KEY="your-api-key"
```

## 🔗 Correlation Settings

### Correlation Configuration

```ruby
EzlogsRubyAgent.configure do |config|
  config.correlation do |corr|
    corr.enable_correlation = true
    corr.max_correlation_depth = 10
    corr.thread_safe = true
    corr.auto_generate_correlation_ids = true
  end
end
```

### Custom Correlation

```ruby
# Use custom correlation IDs
config.correlation do |corr|
  corr.auto_generate_correlation_ids = false
  corr.correlation_id_generator = -> { SecureRandom.uuid }
end
```

## 🧪 Development Settings

### Debug Mode

```ruby
# config/environments/development.rb
EzlogsRubyAgent.configure do |config|
  config.debug_mode = true
  config.delivery.flush_interval = 1.0  # Faster flushing in dev
end
```

### Test Mode

```ruby
# config/environments/test.rb
EzlogsRubyAgent.configure do |config|
  config.test_mode = true
  config.delivery.endpoint = nil  # No delivery in tests
end
```

## 📊 Complete Configuration Example

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |config|
  # Core settings
  config.service_name = 'my-awesome-app'
  config.environment = Rails.env
  
  # Instrumentation settings
  config.instrumentation do |inst|
    inst.http = true
    inst.active_record = true
    inst.active_job = true
    inst.sidekiq = defined?(Sidekiq)
    inst.custom = true
  end
  
  # Security settings
  config.security do |security|
    security.auto_detect_pii = true
    security.sensitive_fields = ['password', 'token', 'api_key', 'ssn']
    security.max_event_size = 1024 * 1024
    security.custom_pii_patterns = {
      'employee_id' => /\bEMP-\d{6}\b/
    }
  end
  
  # Performance settings
  config.performance do |perf|
    perf.sample_rate = Rails.env.production? ? 0.1 : 1.0
    perf.event_buffer_size = 1000
    perf.max_delivery_connections = 10
    perf.enable_compression = true
    perf.enable_async = true
  end
  
  # Delivery settings
  config.delivery do |delivery|
    delivery.endpoint = ENV['EZLOGS_ENDPOINT']
    delivery.timeout = 30
    delivery.flush_interval = Rails.env.production? ? 2.0 : 5.0
    delivery.batch_size = Rails.env.production? ? 200 : 100
    delivery.retry_attempts = 3
    delivery.retry_backoff = 2.0
    delivery.circuit_breaker_threshold = 5
    delivery.circuit_breaker_timeout = 60
    delivery.headers = {
      'X-API-Key' => ENV['EZLOGS_API_KEY'],
      'X-Environment' => Rails.env,
      'X-Service-Name' => config.service_name
    }
  end
  
  # Correlation settings
  config.correlation do |corr|
    corr.enable_correlation = true
    corr.max_correlation_depth = 10
    corr.thread_safe = true
    corr.auto_generate_correlation_ids = true
  end
  
  # Resource filtering
  config.included_resources = ['order', 'user', 'payment']
  config.excluded_resources = ['temp', 'cache', 'session']
end
```

## 🔍 Configuration Validation

### Check Configuration

```ruby
# Validate configuration
puts EzlogsRubyAgent.config.to_s

# Check specific settings
puts "Service Name: #{EzlogsRubyAgent.config.service_name}"
puts "Environment: #{EzlogsRubyAgent.config.environment}"
puts "HTTP Tracking: #{EzlogsRubyAgent.config.instrumentation.http}"
puts "PII Detection: #{EzlogsRubyAgent.config.security.auto_detect_pii}"
```

### Health Check

```ruby
# Check delivery engine health
status = EzlogsRubyAgent.delivery_engine.health_status
puts "Circuit Breaker: #{status[:circuit_breaker_state]}"
puts "Connection Pool: #{status[:connection_pool_size]}"
puts "Success Rate: #{status[:successful_requests]}/#{status[:total_requests]}"
```

## 🚨 Common Configuration Issues

### Events Not Being Delivered

1. **Check endpoint configuration**:
   ```ruby
   puts EzlogsRubyAgent.config.delivery.endpoint
   ```

2. **Verify network connectivity**:
   ```ruby
   require 'net/http'
   uri = URI(EzlogsRubyAgent.config.delivery.endpoint)
   response = Net::HTTP.get_response(uri)
   puts "Endpoint reachable: #{response.code}"
   ```

3. **Check circuit breaker status**:
   ```ruby
   status = EzlogsRubyAgent.delivery_engine.health_status
   puts "Circuit Breaker: #{status[:circuit_breaker_state]}"
   ```

### Performance Issues

1. **Monitor buffer size**:
   ```ruby
   puts "Buffer size: #{EzlogsRubyAgent.config.performance.event_buffer_size}"
   ```

2. **Check delivery metrics**:
   ```ruby
   metrics = EzlogsRubyAgent.delivery_engine.metrics
   puts "Average response time: #{metrics[:average_response_time]}ms"
   ```

3. **Adjust sampling rate**:
   ```ruby
   # Reduce sampling for high-traffic apps
   config.performance.sample_rate = 0.1
   ```

### Security Concerns

1. **Verify PII detection**:
   ```ruby
   puts "PII Detection: #{EzlogsRubyAgent.config.security.auto_detect_pii}"
   puts "Sensitive Fields: #{EzlogsRubyAgent.config.security.sensitive_fields}"
   ```

2. **Check event size limits**:
   ```ruby
   puts "Max Event Size: #{EzlogsRubyAgent.config.security.max_event_size}"
   ```

## 📚 Next Steps

- **[Getting Started](getting-started.md)** - Basic setup and usage
- **[Performance Guide](performance.md)** - Optimization and tuning
- **[Security Guide](security.md)** - Security best practices
- **[API Reference](../lib/ezlogs_ruby_agent.rb)** - Complete API documentation

---

**Your configuration is now optimized for your specific use case!** 🚀 