# Performance Guide

EZLogs Ruby Agent is designed for sub-1ms event creation and high-throughput production workloads. This guide covers optimization strategies and performance tuning.

## ⚡ Performance Characteristics

### Sub-1ms Event Creation

EZLogs Ruby Agent is optimized for minimal overhead:

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
# Output: Average event creation time: 0.5ms
```

### Production Performance Targets

- **Event Creation**: < 1ms per event
- **Memory Usage**: < 5KB per event when serialized
- **Concurrent Throughput**: > 10,000 events/second
- **Zero Memory Leaks**: Continuous operation without memory growth

## 🚀 Performance Optimization

### Sampling for High-Traffic Applications

For high-traffic applications, use sampling to reduce overhead:

```ruby
EzlogsRubyAgent.configure do |config|
  config.performance do |perf|
    # Sample 10% of events in production
    perf.sample_rate = Rails.env.production? ? 0.1 : 1.0
    
    # Larger buffer for batch processing
    perf.event_buffer_size = 5000
    
    # More delivery connections
    perf.max_delivery_connections = 20
  end
end
```

### Buffer Size Optimization

Optimize buffer size based on your traffic patterns:

```ruby
# Low traffic (development)
config.performance.event_buffer_size = 100

# Medium traffic
config.performance.event_buffer_size = 1000

# High traffic (production)
config.performance.event_buffer_size = 5000
```

### Delivery Optimization

Optimize delivery settings for your network conditions:

```ruby
config.delivery do |delivery|
  # Faster flushing for real-time applications
  delivery.flush_interval = 1.0
  
  # Larger batches for efficiency
  delivery.batch_size = 200
  
  # More retries for reliability
  delivery.retry_attempts = 5
  
  # Faster backoff for quick recovery
  delivery.retry_backoff = 1.5
end
```

## 📊 Performance Monitoring

### Health Status

Monitor the delivery engine health:

```ruby
# Check delivery engine health
status = EzlogsRubyAgent.delivery_engine.health_status
puts "Circuit Breaker: #{status[:circuit_breaker_state]}"
puts "Connection Pool: #{status[:connection_pool_size]}"
puts "Success Rate: #{status[:successful_requests]}/#{status[:total_requests]}"
puts "Queue Size: #{status[:queue_size]}"
```

### Metrics Collection

Collect performance metrics:

```ruby
# Get delivery metrics
metrics = EzlogsRubyAgent.delivery_engine.metrics
puts "Average Response Time: #{metrics[:average_response_time]}ms"
puts "Total Events Delivered: #{metrics[:successful_requests]}"
puts "Failed Deliveries: #{metrics[:failed_requests]}"
puts "Success Rate: #{(metrics[:successful_requests].to_f / metrics[:total_requests] * 100).round(2)}%"
```

### Memory Monitoring

Monitor memory usage:

```ruby
# Check memory usage
memory_stats = EzlogsRubyAgent.writer.memory_stats
puts "Buffer Size: #{memory_stats[:buffer_size]}"
puts "Memory Usage: #{memory_stats[:memory_usage]}KB"
puts "Events in Buffer: #{memory_stats[:events_in_buffer]}"
```

## 🔧 Performance Tuning

### Environment-Specific Tuning

```ruby
# config/environments/development.rb
EzlogsRubyAgent.configure do |config|
  config.performance do |perf|
    perf.sample_rate = 1.0        # 100% sampling in dev
    perf.event_buffer_size = 100  # Smaller buffer
    perf.max_delivery_connections = 5
  end
  
  config.delivery do |delivery|
    delivery.flush_interval = 1.0  # Faster flushing
  end
end

# config/environments/production.rb
EzlogsRubyAgent.configure do |config|
  config.performance do |perf|
    perf.sample_rate = 0.1        # 10% sampling in production
    perf.event_buffer_size = 5000 # Larger buffer
    perf.max_delivery_connections = 20
  end
  
  config.delivery do |delivery|
    delivery.flush_interval = 2.0  # Efficient batching
    delivery.batch_size = 200      # Larger batches
  end
end
```

### Traffic-Based Tuning

```ruby
# Dynamic performance tuning based on traffic
class PerformanceTuner
  def self.adjust_for_traffic
    current_load = measure_current_load
    
    case current_load
    when :low
      EzlogsRubyAgent.config.performance.sample_rate = 1.0
      EzlogsRubyAgent.config.performance.event_buffer_size = 1000
    when :medium
      EzlogsRubyAgent.config.performance.sample_rate = 0.5
      EzlogsRubyAgent.config.performance.event_buffer_size = 2000
    when :high
      EzlogsRubyAgent.config.performance.sample_rate = 0.1
      EzlogsRubyAgent.config.performance.event_buffer_size = 5000
    end
  end
  
  private
  
  def self.measure_current_load
    # Your load measurement logic
    :medium
  end
end
```

## 🧪 Performance Testing

### Load Testing

Test performance under load:

```ruby
# Load test script
require 'benchmark'

def load_test
  puts "Starting load test..."
  
  # Warm up
  100.times { create_test_event }
  
  # Performance test
  times = []
  1000.times do
    time = Benchmark.realtime { create_test_event }
    times << time * 1000 # Convert to milliseconds
  end
  
  # Calculate statistics
  avg_time = times.sum / times.length
  p95_time = times.sort[times.length * 0.95]
  p99_time = times.sort[times.length * 0.99]
  
  puts "Average: #{avg_time.round(2)}ms"
  puts "95th percentile: #{p95_time.round(2)}ms"
  puts "99th percentile: #{p99_time.round(2)}ms"
  puts "Max: #{times.max.round(2)}ms"
end

def create_test_event
  EzlogsRubyAgent.log_event(
    event_type: 'load.test',
    action: 'event.created',
    actor: { type: 'system', id: 'load_test' },
    metadata: { timestamp: Time.now.to_f }
  )
end

load_test
```

### Memory Testing

Test memory usage over time:

```ruby
# Memory test script
def memory_test
  puts "Starting memory test..."
  
  initial_memory = get_memory_usage
  puts "Initial memory: #{initial_memory}MB"
  
  # Create events for 1 minute
  start_time = Time.now
  event_count = 0
  
  while Time.now - start_time < 60
    create_test_event
    event_count += 1
    
    if event_count % 1000 == 0
      current_memory = get_memory_usage
      puts "Events: #{event_count}, Memory: #{current_memory}MB"
    end
  end
  
  final_memory = get_memory_usage
  memory_growth = final_memory - initial_memory
  
  puts "Final memory: #{final_memory}MB"
  puts "Memory growth: #{memory_growth}MB"
  puts "Total events: #{event_count}"
  puts "Memory per event: #{(memory_growth * 1024 * 1024 / event_count).round(2)} bytes"
end

def get_memory_usage
  # Get process memory usage in MB
  `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
end

memory_test
```

## 🚨 Performance Issues & Solutions

### High Memory Usage

**Symptoms:**
- Memory usage growing over time
- High buffer sizes
- Slow garbage collection

**Solutions:**
```ruby
# Reduce buffer size
config.performance.event_buffer_size = 1000

# Enable compression
config.performance.enable_compression = true

# Reduce sampling rate
config.performance.sample_rate = 0.1
```

### Slow Event Creation

**Symptoms:**
- Event creation taking > 1ms
- High CPU usage
- Slow application response

**Solutions:**
```ruby
# Use async processing
config.performance.enable_async = true

# Reduce event complexity
# Avoid large metadata objects
# Use simple data types

# Optimize actor/subject extraction
# Cache expensive lookups
```

### Delivery Bottlenecks

**Symptoms:**
- Events not being delivered
- High queue sizes
- Circuit breaker trips

**Solutions:**
```ruby
# Increase delivery connections
config.performance.max_delivery_connections = 20

# Optimize delivery settings
config.delivery do |delivery|
  delivery.flush_interval = 1.0
  delivery.batch_size = 200
  delivery.retry_attempts = 5
end

# Check network connectivity
# Verify endpoint availability
# Monitor circuit breaker status
```

## 📈 Performance Best Practices

### Event Design

1. **Keep events small**:
   ```ruby
   # Good: Small, focused events
   EzlogsRubyAgent.log_event(
     event_type: 'user.action',
     action: 'login',
     actor: { type: 'user', id: user.id },
     metadata: { method: 'email' }
   )
   
   # Avoid: Large, complex events
   EzlogsRubyAgent.log_event(
     event_type: 'user.action',
     action: 'login',
     actor: { type: 'user', id: user.id },
     metadata: { 
       user: user.attributes,  # Don't include full objects
       session: session_data,  # Don't include large data
       request: request_data   # Don't include request objects
     }
   )
   ```

2. **Use simple data types**:
   ```ruby
   # Good: Simple types
   metadata: { count: 5, amount: 99.99, active: true }
   
   # Avoid: Complex objects
   metadata: { user: user, order: order, payment: payment }
   ```

3. **Cache expensive lookups**:
   ```ruby
   # Cache user lookups
   @current_user_id ||= current_user&.id
   
   EzlogsRubyAgent.log_event(
     event_type: 'order.action',
     action: 'created',
     actor: { type: 'user', id: @current_user_id }
   )
   ```

### Configuration Optimization

1. **Environment-specific settings**:
   ```ruby
   # Development: Full sampling, fast delivery
   # Production: Reduced sampling, efficient batching
   ```

2. **Monitor and adjust**:
   ```ruby
   # Regular performance monitoring
   # Adjust settings based on metrics
   # Test changes in staging
   ```

3. **Use appropriate sampling**:
   ```ruby
   # High-traffic: 1-10% sampling
   # Medium-traffic: 10-50% sampling
   # Low-traffic: 100% sampling
   ```

## 🔍 Performance Monitoring

### Key Metrics to Monitor

1. **Event Creation Time**: Should be < 1ms
2. **Memory Usage**: Should be stable over time
3. **Delivery Success Rate**: Should be > 95%
4. **Queue Size**: Should be manageable
5. **Circuit Breaker Status**: Should be closed (healthy)

### Monitoring Setup

```ruby
# Regular health checks
def monitor_ezlogs_health
  status = EzlogsRubyAgent.delivery_engine.health_status
  metrics = EzlogsRubyAgent.delivery_engine.metrics
  
  # Log health status
  Rails.logger.info "EZLogs Health: #{status}"
  Rails.logger.info "EZLogs Metrics: #{metrics}"
  
  # Alert on issues
  if status[:circuit_breaker_state] == 'open'
    alert_team("EZLogs circuit breaker is open")
  end
  
  if metrics[:success_rate] < 0.95
    alert_team("EZLogs delivery success rate is low: #{metrics[:success_rate]}")
  end
end

# Run every 5 minutes
every 5.minutes do
  monitor_ezlogs_health
end
```

## 📚 Next Steps

- **[Getting Started](getting-started.md)** - Basic setup and usage
- **[Configuration Guide](configuration.md)** - Advanced configuration options
- **[Security Guide](security.md)** - Security best practices
- **[API Reference](../lib/ezlogs_ruby_agent.rb)** - Complete API documentation

---

**Your EZLogs Ruby Agent is now optimized for maximum performance!** 🚀 