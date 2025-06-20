# Delivery System Guide

EZLogs Ruby Agent delivers events to your Go server via a robust, production-ready delivery system with circuit breakers, connection pooling, and automatic retries.

## 🌐 Event Delivery Overview

### Where Events Are Sent

Events are delivered to your **Go server** via HTTP POST requests:

```ruby
# Configure your Go server endpoint
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    delivery.endpoint = 'https://logs.your-domain.com/events'
  end
end
```

### Delivery Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Rails App     │───▶│  DeliveryEngine  │───▶│   Go Server     │
│                 │    │                  │    │                 │
│ • HTTP Events   │    │ • Circuit Breaker│    │ • /events       │
│ • DB Changes    │    │ • Connection Pool│    │ • Batch Support │
│ • Job Events    │    │ • Retry Logic    │    │ • Compression   │
│ • Sidekiq       │    │ • Compression    │    │ • Correlation   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🚀 Basic Configuration

### Simple Setup

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    delivery.endpoint = 'https://logs.your-domain.com/events'
  end
end
```

### Environment Variables

```bash
# Set your Go server endpoint
export EZLOGS_ENDPOINT="https://logs.your-domain.com/events"
export EZLOGS_API_KEY="your-api-key"
```

## ⚡ Production Configuration

### Optimized for Production

```ruby
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    # Go server endpoint
    delivery.endpoint = 'https://logs.your-domain.com/events'
    
    # Performance settings
    delivery.timeout = 30
    delivery.flush_interval = 2.0        # Faster flushing
    delivery.batch_size = 200            # Larger batches
    delivery.retry_attempts = 5          # More retries
    delivery.retry_backoff = 1.5         # Faster backoff
    
    # Circuit breaker settings
    delivery.circuit_breaker_threshold = 10
    delivery.circuit_breaker_timeout = 120
    
    # Authentication
    delivery.headers = {
      'X-API-Key' => ENV['EZLOGS_API_KEY'],
      'X-Environment' => Rails.env,
      'X-Service-Name' => config.service_name
    }
  end
end
```

## 🔄 Delivery Process

### Event Flow

1. **Event Creation**: Events are created in your Rails app
2. **Buffering**: Events are buffered in memory
3. **Batching**: Events are grouped into batches
4. **Delivery**: Batches are sent to your Go server
5. **Retry**: Failed deliveries are retried automatically
6. **Circuit Breaker**: Prevents cascading failures

### Batch Processing

```ruby
# Events are automatically batched for efficiency
# No additional configuration needed

# Example batch:
[
  {
    "event_type": "http.request",
    "action": "POST /orders",
    "timestamp": "2024-01-15T10:30:00Z",
    "correlation": { "correlation_id": "corr_abc123" }
  },
  {
    "event_type": "data.change", 
    "action": "order.create",
    "timestamp": "2024-01-15T10:30:01Z",
    "correlation": { "correlation_id": "corr_abc123" }
  }
]
```

## 🛡️ Circuit Breaker

### Automatic Failure Protection

The circuit breaker prevents cascading failures when your Go server is down:

```ruby
# Circuit breaker states:
# CLOSED: Normal operation, requests allowed
# OPEN: Server failing, requests blocked
# HALF_OPEN: Testing if server recovered

# Check circuit breaker status
status = EzlogsRubyAgent.delivery_engine.health_status
puts "Circuit Breaker: #{status[:circuit_breaker_state]}"
```

### Circuit Breaker Configuration

```ruby
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    # Number of failures before opening circuit
    delivery.circuit_breaker_threshold = 5
    
    # Time to wait before testing recovery
    delivery.circuit_breaker_timeout = 60
    
    # Percentage of requests to allow in half-open state
    delivery.circuit_breaker_ratio = 0.5
  end
end
```

## 🔁 Retry Logic

### Automatic Retries

Failed deliveries are automatically retried:

```ruby
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    # Number of retry attempts
    delivery.retry_attempts = 3
    
    # Exponential backoff multiplier
    delivery.retry_backoff = 2.0
    
    # Maximum delay between retries
    delivery.retry_max_delay = 60
    
    # Retry only on specific HTTP status codes
    delivery.retry_status_codes = [500, 502, 503, 504]
  end
end
```

### Retry Behavior

```ruby
# Retry sequence example:
# Attempt 1: Immediate
# Attempt 2: After 2 seconds (2.0 * 1)
# Attempt 3: After 4 seconds (2.0 * 2)
# Attempt 4: After 8 seconds (2.0 * 4)
# Maximum: 60 seconds
```

## 🔗 Connection Pooling

### Efficient HTTP Connections

Connection pooling reduces overhead:

```ruby
EzlogsRubyAgent.configure do |config|
  config.performance do |perf|
    # Number of HTTP connections to maintain
    perf.max_delivery_connections = 10
    
    # Connection timeout
    perf.connection_timeout = 30
    
    # Keep-alive settings
    perf.keep_alive = true
    perf.keep_alive_timeout = 60
  end
end
```

### Connection Pool Benefits

- **Reuse Connections**: Avoid connection setup overhead
- **Parallel Delivery**: Multiple concurrent requests
- **Automatic Cleanup**: Idle connections are closed
- **Load Balancing**: Distribute load across connections

## 📦 Compression

### Automatic Compression

Large payloads are automatically compressed:

```ruby
EzlogsRubyAgent.configure do |config|
  config.performance do |perf|
    # Enable gzip compression
    perf.enable_compression = true
    
    # Compression threshold (bytes)
    perf.compression_threshold = 1024
    
    # Compression level (1-9)
    perf.compression_level = 6
  end
end
```

### Compression Benefits

- **Reduced Bandwidth**: Smaller payload sizes
- **Faster Delivery**: Less data to transfer
- **Cost Savings**: Lower bandwidth costs
- **Automatic**: No configuration needed

## 📊 Monitoring & Metrics

### Health Status

Monitor delivery engine health:

```ruby
# Get comprehensive health status
status = EzlogsRubyAgent.delivery_engine.health_status

puts "Circuit Breaker: #{status[:circuit_breaker_state]}"
puts "Connection Pool: #{status[:connection_pool_size]}"
puts "Queue Size: #{status[:queue_size]}"
puts "Success Rate: #{status[:successful_requests]}/#{status[:total_requests]}"
puts "Average Response Time: #{status[:average_response_time]}ms"
```

### Delivery Metrics

```ruby
# Get detailed metrics
metrics = EzlogsRubyAgent.delivery_engine.metrics

puts "Total Events Delivered: #{metrics[:successful_requests]}"
puts "Failed Deliveries: #{metrics[:failed_requests]}"
puts "Success Rate: #{(metrics[:successful_requests].to_f / metrics[:total_requests] * 100).round(2)}%"
puts "Average Response Time: #{metrics[:average_response_time]}ms"
puts "Total Bytes Sent: #{metrics[:total_bytes_sent]}"
puts "Compression Ratio: #{metrics[:compression_ratio]}"
```

### Real-time Monitoring

```ruby
# Monitor delivery in real-time
def monitor_delivery_health
  status = EzlogsRubyAgent.delivery_engine.health_status
  metrics = EzlogsRubyAgent.delivery_engine.metrics
  
  # Log health status
  Rails.logger.info "Delivery Health: #{status}"
  Rails.logger.info "Delivery Metrics: #{metrics}"
  
  # Alert on issues
  if status[:circuit_breaker_state] == 'open'
    alert_team("Delivery circuit breaker is open")
  end
  
  if metrics[:success_rate] < 0.95
    alert_team("Delivery success rate is low: #{metrics[:success_rate]}")
  end
  
  if status[:queue_size] > 1000
    alert_team("Delivery queue is backing up: #{status[:queue_size]} events")
  end
end

# Run every 5 minutes
every 5.minutes do
  monitor_delivery_health
end
```

## 🚨 Troubleshooting

### Common Issues

#### Events Not Being Delivered

```ruby
# 1. Check endpoint configuration
puts EzlogsRubyAgent.config.delivery.endpoint

# 2. Verify network connectivity
require 'net/http'
uri = URI(EzlogsRubyAgent.config.delivery.endpoint)
response = Net::HTTP.get_response(uri)
puts "Endpoint reachable: #{response.code}"

# 3. Check circuit breaker status
status = EzlogsRubyAgent.delivery_engine.health_status
puts "Circuit Breaker: #{status[:circuit_breaker_state]}"

# 4. Check queue size
puts "Queue Size: #{status[:queue_size]}"
```

#### High Queue Size

```ruby
# Reduce queue size by adjusting settings
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    # Faster flushing
    delivery.flush_interval = 1.0
    
    # Larger batches
    delivery.batch_size = 500
    
    # More delivery connections
    config.performance.max_delivery_connections = 20
  end
end
```

#### Circuit Breaker Trips

```ruby
# Check why circuit breaker opened
status = EzlogsRubyAgent.delivery_engine.health_status
puts "Circuit Breaker State: #{status[:circuit_breaker_state]}"
puts "Failure Count: #{status[:failure_count]}"
puts "Last Failure: #{status[:last_failure_time]}"

# Reset circuit breaker (use with caution)
EzlogsRubyAgent.delivery_engine.reset_circuit_breaker
```

### Debug Mode

Enable debug mode to see delivery details:

```ruby
# Enable debug logging
EzlogsRubyAgent.configure do |config|
  config.debug_mode = true
end

# Debug information will be logged:
# - Delivery attempts
# - Response times
# - Circuit breaker state changes
# - Retry attempts
```

## 🔧 Advanced Configuration

### Custom Headers

```ruby
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    delivery.headers = {
      'X-API-Key' => ENV['EZLOGS_API_KEY'],
      'X-Service-Name' => config.service_name,
      'X-Environment' => Rails.env,
      'X-Version' => '1.0.0',
      'User-Agent' => 'EzlogsRubyAgent/0.1.19'
    }
  end
end
```

### Custom Retry Logic

```ruby
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    # Custom retry function
    delivery.retry_strategy = ->(attempt, error) do
      case error
      when Net::TimeoutError
        attempt < 3  # Retry timeouts up to 3 times
      when Net::HTTPError
        error.response.code.to_i >= 500  # Retry server errors
      else
        false  # Don't retry other errors
      end
    end
  end
end
```

### Custom Circuit Breaker

```ruby
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    # Custom circuit breaker function
    delivery.circuit_breaker_strategy = ->(failures, last_failure_time) do
      # Open circuit if more than 5 failures in last minute
      failures > 5 && (Time.now - last_failure_time) < 60
    end
  end
end
```

## 📈 Performance Optimization

### High-Traffic Applications

```ruby
# Optimize for high traffic
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    # Faster flushing for real-time applications
    delivery.flush_interval = 1.0
    
    # Larger batches for efficiency
    delivery.batch_size = 500
    
    # More retries for reliability
    delivery.retry_attempts = 5
    
    # Faster backoff for quick recovery
    delivery.retry_backoff = 1.5
  end
  
  config.performance do |perf|
    # More delivery connections
    perf.max_delivery_connections = 20
    
    # Enable compression
    perf.enable_compression = true
    
    # Larger buffer for batching
    perf.event_buffer_size = 5000
  end
end
```

### Low-Traffic Applications

```ruby
# Optimize for low traffic
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    # Slower flushing to batch more events
    delivery.flush_interval = 10.0
    
    # Smaller batches
    delivery.batch_size = 50
    
    # Fewer retries
    delivery.retry_attempts = 2
  end
  
  config.performance do |perf|
    # Fewer connections
    perf.max_delivery_connections = 5
    
    # Smaller buffer
    perf.event_buffer_size = 100
  end
end
```

## 🔒 Security

### HTTPS Only

```ruby
# Force HTTPS connections
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    delivery.require_ssl = true
    delivery.ssl_verify_mode = OpenSSL::SSL::VERIFY_PEER
  end
end
```

### Authentication

```ruby
# API key authentication
EzlogsRubyAgent.configure do |config|
  config.delivery do |delivery|
    delivery.headers = {
      'X-API-Key' => ENV['EZLOGS_API_KEY'],
      'Authorization' => "Bearer #{ENV['EZLOGS_API_KEY']}"
    }
  end
end
```

## 📚 Next Steps

- **[Getting Started](getting-started.md)** - Basic setup and usage
- **[Configuration Guide](configuration.md)** - Advanced configuration options
- **[Performance Guide](performance.md)** - Optimization and tuning
- **[Security Guide](security.md)** - Security best practices
- **[API Reference](../lib/ezlogs_ruby_agent.rb)** - Complete API documentation

---

**Your EZLogs Ruby Agent delivery system is now optimized for production!** 🚀 