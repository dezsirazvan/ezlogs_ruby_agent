# Configuration Guide

EZLogs Ruby Agent provides a powerful configuration system that works out of the box while allowing fine-grained customization for production environments.

## Zero-Config Defaults

EZLogs works immediately with sensible defaults:

```ruby
# No configuration needed - just works!
EzlogsRubyAgent.configure do |config|
  # All defaults are production-ready
end
```

## Core Settings

### Basic Configuration

```ruby
EzlogsRubyAgent.configure do |config|
  config.service_name = 'my-awesome-app'
  config.environment = Rails.env
  
  # Or use the quick setup method
  config.quick_setup(
    service_name: 'my-awesome-app',
    environment: Rails.env
  )
end
```

### Environment Variables

You can also configure via environment variables:

```bash
export EZLOGS_SERVICE_NAME="my-awesome-app"
export EZLOGS_ENVIRONMENT="production"
export EZLOGS_ENDPOINT="https://logs.ezlogs.com/events"
```

## Instrumentation Configuration

Control which Rails components are automatically tracked:

```ruby
EzlogsRubyAgent.configure do |config|
  config.instrumentation do |instrumentation|
    instrumentation.http = true          # Track HTTP requests
    instrumentation.active_record = true # Track database changes
    instrumentation.active_job = true    # Track background jobs
    instrumentation.sidekiq = true       # Track Sidekiq jobs
    instrumentation.custom = true        # Allow custom events
  end
end
```

## Security Configuration

### PII Detection and Sanitization

```ruby
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    # Automatic PII detection (enabled by default)
    security.auto_detect_pii = true
    
    # Fields that are always sanitized
    security.sensitive_fields = %w[
      password token api_key secret key 
      authorization bearer ssn credit_card
    ]
    
    # Custom PII patterns for your domain
    security.custom_pii_patterns = {
      'employee_id' => /\bEMP-\d{6}\b/,
      'customer_code' => /\bCUST-[A-Z]{2}\d{4}\b/,
      'internal_ip' => /\b(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)\d+\.\d+\b/
    }
    
    # Maximum event size (1MB default)
    security.max_event_size = 1024 * 1024
    
    # Headers to redact
    security.redacted_headers = %w[
      authorization x-api-key x-auth-token
      x-csrf-token cookie
    ]
    
    # Cookies to redact
    security.redacted_cookies = %w[
      session _csrf_token remember_token
    ]
  end
end
```

### Custom Actor Extraction

You can customize how actors (users) are extracted from requests and resources:

```ruby
EzlogsRubyAgent.configure do |config|
  # Custom actor extraction for your authentication system
  config.actor_extractor = ->(resource) do
    # Example 1: Custom user extraction from JWT token
    if resource.is_a?(Hash) && resource['HTTP_AUTHORIZATION']
      token = resource['HTTP_AUTHORIZATION'].gsub('Bearer ', '')
      user_data = JWT.decode(token, Rails.application.secrets.secret_key_base).first
      
      {
        type: 'user',
        id: user_data['user_id'],
        email: user_data['email'],
        role: user_data['role']
      }
    end
    
    # Example 2: Extract from custom header
    elsif resource.is_a?(Hash) && resource['HTTP_X_USER_ID']
      {
        type: 'user',
        id: resource['HTTP_X_USER_ID'],
        email: resource['HTTP_X_USER_EMAIL']
      }
    end
    
    # Example 3: Extract from API key
    elsif resource.is_a?(Hash) && resource['HTTP_X_API_KEY']
      api_key = resource['HTTP_X_API_KEY']
      api_user = ApiUser.find_by(key: api_key)
      
      if api_user
        {
          type: 'api_user',
          id: api_user.id,
          name: api_user.name,
          permissions: api_user.permissions
        }
      end
    end
    
    # Example 4: Extract from resource object
    elsif resource.respond_to?(:current_user) && resource.current_user
      user = resource.current_user
      {
        type: 'user',
        id: user.id,
        email: user.email,
        role: user.role,
        organization_id: user.organization_id
      }
    end
    
    # Return nil to fall back to default extraction
    nil
  end
end
```

### Advanced Actor Extraction Examples

```ruby
# Multi-tenant application with organization context
config.actor_extractor = ->(resource) do
  user = extract_user(resource)
  return nil unless user
  
  {
    type: 'user',
    id: user.id,
    email: user.email,
    organization_id: user.organization_id,
    tenant_id: user.tenant_id,
    permissions: user.permissions
  }
end

# Microservice with service-to-service authentication
config.actor_extractor = ->(resource) do
  if resource.is_a?(Hash) && resource['HTTP_X_SERVICE_TOKEN']
    service_token = resource['HTTP_X_SERVICE_TOKEN']
    service = ServiceRegistry.find_by_token(service_token)
    
    {
      type: 'service',
      id: service.id,
      name: service.name,
      version: service.version,
      environment: service.environment
    }
  end
end

# OAuth2 application with multiple providers
config.actor_extractor = ->(resource) do
  if resource.is_a?(Hash) && resource['HTTP_AUTHORIZATION']
    token = resource['HTTP_AUTHORIZATION'].gsub('Bearer ', '')
    
    case token.split('.').first
    when 'google'
      user_data = GoogleAuth.verify_token(token)
      {
        type: 'google_user',
        id: user_data['sub'],
        email: user_data['email'],
        provider: 'google'
      }
    when 'github'
      user_data = GitHubAuth.verify_token(token)
      {
        type: 'github_user',
        id: user_data['id'],
        username: user_data['login'],
        provider: 'github'
      }
    end
  end
end
```

## Performance Configuration

### Sampling and Buffering

```ruby
EzlogsRubyAgent.configure do |config|
  config.performance do |performance|
    # Sample rate (1.0 = 100% of events)
    performance.sample_rate = 1.0
    
    # Buffer size for batching events
    performance.event_buffer_size = 1000
    
    # Maximum concurrent delivery connections
    performance.max_delivery_connections = 10
    
    # Enable compression for large payloads
    performance.enable_compression = true
    
    # Enable async processing (recommended)
    performance.enable_async = true
  end
end
```

### Production Performance Tuning

```ruby
# High-traffic production settings
config.performance do |performance|
  performance.sample_rate = 0.1        # 10% sampling
  performance.event_buffer_size = 5000 # Larger buffer
  performance.max_delivery_connections = 20
  performance.enable_compression = true
  performance.enable_async = true
end

# Development settings
config.performance do |performance|
  performance.sample_rate = 1.0        # 100% sampling
  performance.event_buffer_size = 100  # Smaller buffer
  performance.max_delivery_connections = 5
  performance.enable_compression = false
  performance.enable_async = false     # Synchronous for debugging
end
```

## Delivery Configuration

### Endpoint and Connection Settings

```ruby
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    # EZLogs endpoint (required for production)
    delivery.endpoint = 'https://logs.ezlogs.com/events'
    
    # Connection timeout
    delivery.timeout = 30
    
    # Retry configuration
    delivery.retry_attempts = 3
    delivery.retry_backoff = 1.0
    
    # Batching configuration
    delivery.batch_size = 100
    delivery.flush_interval = 5.0
    
    # Custom headers (for authentication, etc.)
    delivery.headers = {
      'Authorization' => 'Bearer your-api-key',
      'X-Service-Version' => '1.0.0'
    }
    
    # Circuit breaker settings
    delivery.circuit_breaker_threshold = 5
    delivery.circuit_breaker_timeout = 60
  end
end
```

### Environment-Specific Delivery

```ruby
# Production delivery
if Rails.env.production?
  config.delivery do |delivery|
    delivery.endpoint = 'https://logs.ezlogs.com/events'
    delivery.headers = {
      'Authorization' => "Bearer #{ENV['EZLOGS_API_KEY']}"
    }
    delivery.batch_size = 500
    delivery.flush_interval = 2.0
  end
end

# Staging delivery
if Rails.env.staging?
  config.delivery do |delivery|
    delivery.endpoint = 'https://staging-logs.ezlogs.com/events'
    delivery.headers = {
      'Authorization' => "Bearer #{ENV['EZLOGS_STAGING_KEY']}"
    }
    delivery.batch_size = 100
    delivery.flush_interval = 5.0
  end
end

# Development delivery (local testing)
if Rails.env.development?
  config.delivery do |delivery|
    delivery.endpoint = 'http://localhost:3001/events'
    delivery.batch_size = 10
    delivery.flush_interval = 1.0
  end
end
```

## Correlation Configuration

### Flow Tracking Settings

```ruby
EzlogsRubyAgent.configure do |config|
  config.correlation do |correlation|
    # Enable correlation tracking (enabled by default)
    correlation.enable_correlation = true
    
    # Maximum correlation depth for nested operations
    correlation.max_correlation_depth = 10
    
    # Thread safety for correlation context
    correlation.thread_safe = true
    
    # Auto-generate correlation IDs
    correlation.auto_generate_correlation_ids = true
  end
end
```

## Resource Filtering

### Include/Exclude Specific Resources

```ruby
EzlogsRubyAgent.configure do |config|
  # Only track specific models
  config.included_resources = %w[User Order Payment]
  
  # Exclude specific models
  config.excluded_resources = %w[AuditLog SessionToken]
  
  # Or use patterns
  config.included_resources = [/User/, /Order/, /Payment/]
  config.excluded_resources = [/Temp/, /Cache/, /Log/]
end
```

## Environment-Specific Overrides

### Conditional Configuration

```ruby
EzlogsRubyAgent.configure do |config|
  # Base configuration
  config.service_name = 'my-app'
  
  # Environment-specific overrides
  case Rails.env
  when 'production'
    config.performance.sample_rate = 0.1
    config.delivery.endpoint = 'https://logs.ezlogs.com/events'
    config.security.max_event_size = 2 * 1024 * 1024 # 2MB
    
  when 'staging'
    config.performance.sample_rate = 0.5
    config.delivery.endpoint = 'https://staging-logs.ezlogs.com/events'
    
  when 'development'
    config.performance.sample_rate = 1.0
    config.delivery.endpoint = 'http://localhost:3001/events'
    config.performance.enable_async = false
  end
end
```

## Configuration Validation

### Validate Your Configuration

```ruby
# Validate configuration before starting
validation = EzlogsRubyAgent.config.validate!

if validation.valid?
  puts "✅ Configuration is valid!"
else
  puts "❌ Configuration errors:"
  validation.errors.each { |error| puts "  - #{error}" }
end

if validation.warnings.any?
  puts "⚠️  Configuration warnings:"
  validation.warnings.each { |warning| puts "  - #{warning}" }
end
```

### Configuration Summary

```ruby
# Get a summary of your configuration
puts EzlogsRubyAgent.config.summary
```

## Troubleshooting

### Common Configuration Issues

```ruby
# Issue: Events not being delivered
# Solution: Check endpoint and authentication
config.delivery do |delivery|
  delivery.endpoint = 'https://logs.ezlogs.com/events'
  delivery.headers = {
    'Authorization' => "Bearer #{ENV['EZLOGS_API_KEY']}"
  }
end

# Issue: Too many events in development
# Solution: Reduce sampling or disable async
config.performance do |performance|
  performance.sample_rate = 0.1
  performance.enable_async = false
end

# Issue: Sensitive data in events
# Solution: Configure PII detection
config.security do |security|
  security.sensitive_fields += %w[ssn credit_card]
  security.custom_pii_patterns = {
    'employee_id' => /\bEMP-\d{6}\b/
  }
end
```

### Debug Configuration

```ruby
# Enable debug mode to see configuration details
if Rails.env.development?
  puts "EZLogs Configuration:"
  puts EzlogsRubyAgent.config.summary
  
  # Test actor extraction
  test_resource = { 'HTTP_AUTHORIZATION' => 'Bearer test-token' }
  actor = EzlogsRubyAgent::ActorExtractor.extract_actor(test_resource)
  puts "Actor extraction test: #{actor}"
end
```

## Best Practices

### Production Configuration Checklist

- [ ] Set appropriate `service_name` and `environment`
- [ ] Configure `delivery.endpoint` with authentication
- [ ] Set `performance.sample_rate` based on traffic
- [ ] Configure `security.sensitive_fields` for your domain
- [ ] Set `performance.enable_async = true`
- [ ] Configure `delivery.circuit_breaker_threshold`
- [ ] Test configuration with `config.validate!`

### Security Best Practices

- [ ] Never log sensitive fields (passwords, tokens, etc.)
- [ ] Use environment variables for API keys
- [ ] Configure custom PII patterns for your domain
- [ ] Set appropriate `max_event_size` limits
- [ ] Use HTTPS endpoints in production

### Performance Best Practices

- [ ] Use sampling in high-traffic environments
- [ ] Enable compression for large payloads
- [ ] Configure appropriate buffer sizes
- [ ] Use async processing in production
- [ ] Monitor delivery performance

This configuration system provides the flexibility to adapt EZLogs to any Rails application while maintaining the simplicity of zero-config defaults.

## 📚 Next Steps

- **[Getting Started](getting-started.md)** - Basic setup and usage
- **[Performance Guide](performance.md)** - Optimization and tuning
- **[Security Guide](security.md)** - Security best practices
- **[API Reference](../lib/ezlogs_ruby_agent.rb)** - Complete API documentation

---

**Your configuration is now optimized for your specific use case!** 🚀 