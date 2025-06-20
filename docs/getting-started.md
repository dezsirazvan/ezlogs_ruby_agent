# Getting Started with EZLogs Ruby Agent

Welcome to EZLogs Ruby Agent! This guide will walk you through setting up event tracking in your Rails application in under 5 minutes.

## 🚀 Quick Installation

### 1. Add to Your Gemfile

```ruby
# Gemfile
gem 'ezlogs_ruby_agent'
```

Run bundle install:
```bash
bundle install
```

### 2. Basic Configuration

Create the initializer file:

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |c|
  c.service_name = 'my-awesome-app'
  c.environment = Rails.env
end
```

That's it! EZLogs will automatically start tracking:
- HTTP requests (all API calls and page views)
- Database changes (ActiveRecord create/update/destroy)
- Background jobs (ActiveJob and Sidekiq)

## 🎯 Automatic Event Tracking

After restarting your Rails application, **events are automatically captured** - no additional code needed!

### HTTP Request Events
Every web request generates an event automatically:

```json
{
  "event_type": "http_request",
  "action": "GET",
  "actor": "user_123",
  "subject": "/api/orders",
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "path": "/api/orders",
    "method": "GET",
    "status": 200,
    "duration_ms": 45,
    "user_agent": "Mozilla/5.0...",
    "ip_address": "192.168.1.100"
  }
}
```

### Database Change Events
ActiveRecord operations are automatically tracked:

```json
{
  "event_type": "database_change",
  "action": "created",
  "actor": "user_123",
  "subject": "Order_456",
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "table": "orders",
    "record_id": 456,
    "changes": {
      "total": [null, 99.99],
      "status": [null, "pending"]
    }
  }
}
```

### Background Job Events
Job execution is tracked automatically:

```json
{
  "event_type": "background_job",
  "action": "completed",
  "actor": "system",
  "subject": "ProcessOrderJob_789",
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "job_class": "ProcessOrderJob",
    "job_id": "789",
    "duration_ms": 1250,
    "queue": "default"
  }
}
```

## 🎯 Custom Business Events (Optional)

For business-specific events beyond the automatic tracking, you can add custom events:

### Basic Event Tracking

Track important business actions in your controllers, models, or services:

```ruby
# In a controller
class OrdersController < ApplicationController
  def create
    order = Order.create!(order_params)
    
    # Track custom business event (optional)
    EzlogsRubyAgent.log_event(
      event_type: 'order',
      action: 'created',
      actor: current_user.id,
      subject: order.id,
      metadata: {
        total: order.total,
        items_count: order.items.count,
        payment_method: order.payment_method
      }
    )
    
    render json: order
  end
end
```

### In Models with Callbacks

```ruby
class Order < ApplicationRecord
  after_create :track_order_creation
  
  private
  
  def track_order_creation
    # Track custom business event (optional)
    EzlogsRubyAgent.log_event(
      event_type: 'order',
      action: 'created',
      actor: user_id,
      subject: id,
      metadata: {
        total: total,
        status: status,
        created_at: created_at
      }
    )
  end
end
```

### In Background Jobs

```ruby
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    
    # Track custom job events (optional)
    EzlogsRubyAgent.log_event(
      event_type: 'order_processing',
      action: 'started',
      actor: 'system',
      subject: order_id,
      metadata: { queue: queue_name }
    )
    
    # Process the order
    order.process!
    
    # Track custom completion event (optional)
    EzlogsRubyAgent.log_event(
      event_type: 'order_processing',
      action: 'completed',
      actor: 'system',
      subject: order_id,
      metadata: { 
        processing_time_ms: Time.current.to_f - started_at,
        final_status: order.status
      }
    )
  end
end
```

## 🔗 Business Process Tracking

Track complex workflows that span multiple operations:

```ruby
class OrderFulfillmentService
  def fulfill_order(order_id)
    # Start a business flow
    EzlogsRubyAgent.start_flow('order_fulfillment', order_id, {
      customer_id: order.customer_id,
      priority: order.priority
    })
    
    begin
      # Reserve inventory
      inventory_result = reserve_inventory(order)
      EzlogsRubyAgent.log_event(
        event_type: 'inventory',
        action: 'reserved',
        subject: order_id,
        metadata: { items_reserved: inventory_result.items_count }
      )
      
      # Process payment
      payment_result = process_payment(order)
      EzlogsRubyAgent.log_event(
        event_type: 'payment',
        action: 'processed',
        subject: order_id,
        metadata: { amount: payment_result.amount }
      )
      
      # Create shipping label
      shipping_result = create_shipping_label(order)
      EzlogsRubyAgent.log_event(
        event_type: 'shipping',
        action: 'label_created',
        subject: order_id,
        metadata: { tracking_number: shipping_result.tracking_number }
      )
      
    rescue => e
      # Track failures
      EzlogsRubyAgent.log_event(
        event_type: 'order_fulfillment',
        action: 'failed',
        subject: order_id,
        metadata: { error: e.message, step: current_step }
      )
      raise
    end
  end
end
```

## ⚡ Performance Monitoring

### Timing Critical Operations

```ruby
# Time expensive operations
def process_payment(order)
  EzlogsRubyAgent.timing('payment_processing') do
    PaymentProcessor.charge(order)
  end
end

# Custom timing with metadata
def complex_operation
  start_time = Time.current
  
  # ... do work ...
  
  duration_ms = (Time.current - start_time) * 1000
  EzlogsRubyAgent.record_metric('complex_operation_duration', duration_ms, {
    operation_type: 'data_processing',
    records_processed: records.count
  })
end
```

### Custom Metrics

```ruby
# Record business metrics
EzlogsRubyAgent.record_metric('orders_per_minute', 1, { 
  region: 'us-east',
  customer_tier: 'premium'
})

# Track user actions
EzlogsRubyAgent.record_metric('user_login', 1, {
  auth_method: 'email',
  success: true
})
```

## 🧪 Development & Testing

### Debug Mode

Enable debug mode in development to see events in real-time:

```ruby
# config/environments/development.rb
EzlogsRubyAgent.debug_mode = true
```

This will:
- Log events to the console
- Capture events in memory for inspection
- Provide detailed error messages

### Test Mode

Use test mode in your test suite to verify event tracking:

```ruby
# spec/support/ezlogs_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    EzlogsRubyAgent.test_mode do
      # All events captured in memory
    end
  end
  
  config.after(:each) do
    EzlogsRubyAgent.clear_captured_events
  end
end
```

### Testing Event Tracking

```ruby
# spec/controllers/orders_controller_spec.rb
RSpec.describe OrdersController, type: :controller do
  it "tracks order creation" do
    post :create, params: { order: { total: 99.99 } }
    
    events = EzlogsRubyAgent.captured_events
    expect(events).to include(
      hash_including(
        event_type: 'order',
        action: 'created',
        metadata: hash_including(total: 99.99)
      )
    )
  end
end
```

## 🔧 Configuration Options

### Basic Configuration

```ruby
EzlogsRubyAgent.configure do |c|
  # Required settings
  c.service_name = 'my-awesome-app'
  c.environment = Rails.env
  
  # Optional: Customize what to track
  c.collect do |collect|
    collect.http_requests = true
    collect.database_changes = true
    collect.background_jobs = true
  end
  
  # Optional: Security settings
  c.security do |security|
    security.auto_detect_pii = true
    security.sanitize_fields = ['password', 'token']
  end
  
  # Optional: Performance tuning
  c.performance do |perf|
    perf.sample_rate = 1.0  # 100% of events
    perf.buffer_size = 1000
  end
end
```

### Environment Variables

You can also configure via environment variables:

```bash
export EZLOGS_SERVICE_NAME="my-awesome-app"
export EZLOGS_ENVIRONMENT="production"
export EZLOGS_SAMPLE_RATE="0.1"
export EZLOGS_BUFFER_SIZE="5000"
```

Then load them in your configuration:

```ruby
EzlogsRubyAgent.configure do |c|
  c.load_from_environment!
end
```

## 🚨 Common Issues & Solutions

### Events Not Appearing

1. **Check configuration**: Ensure `service_name` and `environment` are set
2. **Verify initialization**: Make sure the initializer is loaded
3. **Enable debug mode**: Set `EzlogsRubyAgent.debug_mode = true` to see events

### Performance Issues

1. **Reduce sample rate**: Set `sample_rate` to 0.1 for high-traffic apps
2. **Increase buffer size**: Set `buffer_size` to 5000+ for batch processing
3. **Monitor memory**: Check `EzlogsRubyAgent.health_status`

### Security Concerns

1. **Enable PII detection**: Set `auto_detect_pii = true`
2. **Sanitize sensitive fields**: Add fields to `sanitize_fields` array
3. **Set payload limits**: Configure `max_payload_size`

## 📚 Next Steps

- **[Configuration Guide](configuration.md)** - Advanced configuration options
- **[Performance Guide](performance.md)** - Optimization and tuning
- **[Security Guide](security.md)** - Security best practices
- **[API Reference](../lib/ezlogs_ruby_agent.rb)** - Complete API documentation
- **[Examples](../examples/)** - Complete example applications

## 🆘 Need Help?

- **Documentation**: [https://dezsirazvan.github.io/ezlogs_ruby_agent/](https://dezsirazvan.github.io/ezlogs_ruby_agent/)
- **Issues**: [GitHub Issues](https://github.com/dezsirazvan/ezlogs_ruby_agent/issues)
- **Discussions**: [GitHub Discussions](https://github.com/dezsirazvan/ezlogs_ruby_agent/discussions)

---

**You're all set!** Your Rails application is now tracking events with zero performance impact. Start exploring the data and building AI-powered insights! 🚀 