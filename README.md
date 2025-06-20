# 🚀 EZLogs Ruby Agent

[![Ruby Version](https://img.shields.io/badge/ruby-3.0+-red.svg)](https://www.ruby-lang.org/)
[![Rails Version](https://img.shields.io/badge/rails-5.0+-green.svg)](https://rubyonrails.org/)
[![Test Status](https://img.shields.io/badge/tests-246%20examples%2C%200%20failures-brightgreen.svg)](https://github.com/your-org/ezlogs_ruby_agent)
[![Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen.svg)](https://github.com/your-org/ezlogs_ruby_agent)

**The world's most elegant Rails event tracking gem** - Zero-config, production-ready event collection with perfect correlation across HTTP requests, database changes, background jobs, and Sidekiq.

## ✨ Features

- **🚀 Zero-Config Setup** - Works out of the box with intelligent defaults
- **🔗 Perfect Correlation** - Track events across HTTP → DB → Job → Sidekiq with correlation IDs
- **🛡️ Production-Ready** - Circuit breakers, connection pooling, retry logic, compression
- **🔒 Security First** - Automatic PII detection and sanitization
- **⚡ Sub-1ms Performance** - Optimized for high-throughput applications
- **🧵 Thread-Safe** - Designed for concurrent Rails applications
- **📊 Comprehensive Coverage** - HTTP requests, ActiveRecord callbacks, ActiveJob, Sidekiq

## 🚀 Quick Start

### 1. Install

Add to your Gemfile:

```ruby
gem 'ezlogs_ruby_agent'
```

Run:
```bash
bundle install
```

### 2. Configure

Create `config/initializers/ezlogs_ruby_agent.rb`:

```ruby
EzlogsRubyAgent.configure do |config|
  # Core settings
  config.service_name = 'my-awesome-app'
  config.environment = Rails.env
  
  # Local agent settings (defaults work for most setups)
  config.delivery do |delivery|
    delivery.endpoint = 'http://localhost:8080/events'  # Local Go agent
    delivery.timeout = 30
    delivery.flush_interval = 5.0
  end
end
```

**For development/testing only**, you can use zero-config (events captured in memory):
```ruby
EzlogsRubyAgent.configure do |config|
  # Zero-config for development
end
```

### 3. Deploy

Your Rails app now automatically tracks:
- ✅ HTTP requests
- ✅ Database changes  
- ✅ Background jobs
- ✅ Sidekiq jobs
- ✅ Custom events

All events are correlated with the same ID across the entire request lifecycle!

## 📦 Installation & Setup

### Zero-Config (Development/Testing)

EZLogs Ruby Agent works out of the box for development and testing:

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |config|
  # Service name: Auto-detected from Rails app name
  # Environment: Auto-detected from Rails.env
  # All collectors: Enabled by default
  # Security: PII detection enabled
  # Note: Events are captured in memory for development/testing
end
```

**For production, configure the local Go agent endpoint.**

### Basic Configuration

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |config|
  # Core settings
  config.service_name = 'my-awesome-app'
  config.environment = Rails.env
  
  # Local agent settings (defaults work for most setups)
  config.delivery do |delivery|
    delivery.endpoint = 'http://localhost:8080/events'  # Local Go agent
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

# Local agent settings
export EZLOGS_ENDPOINT="http://localhost:8080/events"
export EZLOGS_TIMEOUT="30"
export EZLOGS_FLUSH_INTERVAL="5.0"
```

## 🔍 What Gets Tracked

### Automatic Event Collection

| Event Type | Description | Example |
|------------|-------------|---------|
| **HTTP Requests** | All web requests | `POST /orders`, `GET /users/123` |
| **Database Changes** | ActiveRecord callbacks | `order.create`, `user.update` |
| **Background Jobs** | ActiveJob execution | `ProcessOrderJob.perform` |
| **Sidekiq Jobs** | Sidekiq job execution | `EmailJob.perform` |

### Perfect Correlation

All events in a single request share the same correlation ID:

```
HTTP Request → Database Change → Background Job → Sidekiq Job
     ↓              ↓                ↓              ↓
corr_abc123    corr_abc123      corr_abc123    corr_abc123
```

## 📊 Event Schema

All events follow a universal schema:

```json
{
  "event": {
    "event_id": "evt_abc123",
    "timestamp": "2025-01-20T10:30:00Z",
    "event_type": "http.request",
    "action": "POST /orders",
    "actor": {
      "type": "user",
      "id": "user_123"
    },
    "subject": {
      "type": "order", 
      "id": "order_456"
    },
    "metadata": {
      "method": "POST",
      "path": "/orders",
      "status": 201,
      "duration": 0.125
    },
    "correlation": {
      "correlation_id": "corr_xyz789"
    },
    "platform": {
      "service": "my-app",
      "environment": "production",
      "agent_version": "0.1.19"
    }
  }
}
```

## 🔧 Usage Examples

### Custom Event Tracking

```ruby
# Track custom business events
EzlogsRubyAgent.log_event(
  event_type: 'order.action',
  action: 'created',
  actor: { type: 'user', id: current_user.id },
  subject: { type: 'order', id: order.id },
  metadata: { amount: order.total, currency: 'USD' }
)
```

### Correlation Across Jobs

```ruby
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    # Correlation context automatically preserved
    order = Order.find(order_id)
    
    # All events in this job will have the same correlation ID
    EzlogsRubyAgent.log_event(
      event_type: 'order.processing',
      action: 'started',
      subject: { type: 'order', id: order.id }
    )
    
    # Process order...
  end
end
```

### HTTP Request Tracking

```ruby
# Automatically tracks all HTTP requests
# No additional code needed!

class OrdersController < ApplicationController
  def create
    order = Order.create!(order_params)
    # HTTP request, DB change, and any job events
    # will all share the same correlation ID
    redirect_to order
  end
end
```

## 🧪 Testing

### Test Mode

```ruby
# spec/spec_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    EzlogsRubyAgent.test_mode do
      # Events captured in memory for testing
    end
  end
  
  config.after(:each) do
    EzlogsRubyAgent.clear_captured_events
  end
end
```

### Event Assertions

```ruby
it "tracks order creation" do
  post "/orders", params: { order: { amount: 100 } }
  
  events = EzlogsRubyAgent.captured_events
  expect(events).to include(
    hash_including(
      event_type: 'http.request',
      action: 'POST /orders'
    )
  )
  
  expect(events).to include(
    hash_including(
      event_type: 'data.change',
      action: 'order.create'
    )
  )
end
```

## 🔒 Security

### PII Protection

```ruby
# Automatic PII detection and sanitization
config.security do |security|
  security.auto_detect_pii = true
  security.sensitive_fields = ['password', 'ssn', 'credit_card']
  security.custom_pii_patterns = {
    'employee_id' => /\bEMP-\d{6}\b/
  }
end
```

### Field Filtering

```ruby
# Include/exclude specific resources
config.included_resources = ['order', 'user', 'payment']
config.excluded_resources = ['temp', 'cache', 'session']
```

## 🚀 Performance

### Sub-1ms Event Creation

```ruby
# Performance benchmark
start_time = Time.now
1000.times do
  EzlogsRubyAgent.log_event(
    event_type: 'test.event',
    action: 'created',
    actor: { type: 'system', id: 'test' }
  )
end
end_time = Time.now

avg_time = (end_time - start_time) * 1000 / 1000
puts "Average event creation time: #{avg_time}ms"
```

### Production Features

- **Circuit Breaker**: Prevents cascading failures
- **Connection Pooling**: Efficient HTTP connection reuse
- **Retry Logic**: Automatic retry with exponential backoff
- **Compression**: Gzip compression for large payloads
- **Batch Delivery**: Efficient batch processing
- **Health Monitoring**: Real-time delivery metrics

## 📈 Monitoring & Debugging

### Health Status

```ruby
# Check delivery engine health
status = EzlogsRubyAgent.delivery_engine.health_status
puts "Circuit Breaker: #{status[:circuit_breaker_state]}"
puts "Connection Pool: #{status[:connection_pool_size]}"
puts "Success Rate: #{status[:successful_requests]}/#{status[:total_requests]}"
```

### Debug Mode

```ruby
# Enable debug logging
EzlogsRubyAgent.configure do |config|
  config.debug_mode = true
end
```

### Metrics

```ruby
# Get delivery metrics
metrics = EzlogsRubyAgent.delivery_engine.metrics
puts "Average Response Time: #{metrics[:average_response_time]}ms"
puts "Total Events Delivered: #{metrics[:successful_requests]}"
```

## 🔧 Advanced Configuration

### Complete Configuration

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |config|
  # Core settings
  config.service_name = 'my-awesome-app'
  config.environment = Rails.env
  
  # Instrumentation settings
  config.instrumentation do |inst|
    inst.http = true              # HTTP request tracking
    inst.active_record = true     # Database change tracking
    inst.active_job = true        # ActiveJob tracking
    inst.sidekiq = true           # Sidekiq job tracking
    inst.custom = true            # Custom event tracking
  end
  
  # Security settings
  config.security do |security|
    security.auto_detect_pii = true
    security.sensitive_fields = ['password', 'token', 'api_key']
    security.max_event_size = 1024 * 1024 # 1MB
    security.custom_pii_patterns = {
      'employee_id' => /\bEMP-\d{6}\b/
    }
  end
  
  # Performance settings
  config.performance do |perf|
    perf.sample_rate = 1.0        # 100% sampling
    perf.event_buffer_size = 1000
    perf.max_delivery_connections = 10
    perf.enable_compression = true
    perf.enable_async = true
  end
  
  # Delivery settings
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
      'X-API-Key' => ENV['EZLOGS_API_KEY']
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
  config.excluded_resources = ['temp', 'cache']
end
```

## 📚 API Reference

### Configuration

```ruby
EzlogsRubyAgent.configure do |config|
  # All configuration options
end
```

### Event Logging

```ruby
EzlogsRubyAgent.log_event(
  event_type: 'namespace.category',
  action: 'specific_action',
  actor: { type: 'user', id: '123' },
  subject: { type: 'resource', id: '456' },
  metadata: { key: 'value' }
)
```

### Test Mode

```ruby
EzlogsRubyAgent.test_mode do
  # Events captured in memory
end

events = EzlogsRubyAgent.captured_events
EzlogsRubyAgent.clear_captured_events
```

## 🐛 Troubleshooting

### Common Issues

1. **Events not being delivered**
   - Check `config.delivery.endpoint` is configured
   - Verify network connectivity to Go server
   - Check circuit breaker status

2. **Performance issues**
   - Monitor event buffer size
   - Check delivery engine metrics
   - Verify compression settings

3. **Correlation not working**
   - Ensure correlation is enabled
   - Check thread safety settings
   - Verify correlation depth limits

### Debug Information

```ruby
# Get comprehensive debug info
puts EzlogsRubyAgent.config.to_s
puts EzlogsRubyAgent.delivery_engine.health_status
puts EzlogsRubyAgent.writer.health_status
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE.txt](LICENSE.txt) for details.

## 🆘 Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/your-org/ezlogs_ruby_agent/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/ezlogs_ruby_agent/discussions)

---

**Built with ❤️ for the Rails community**
