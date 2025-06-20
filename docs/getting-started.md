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
EzlogsRubyAgent.configure do |config|
  config.service_name = 'my-awesome-app'
  config.environment = Rails.env
end
```

That's it! EZLogs will automatically start tracking:
- ✅ HTTP requests (all API calls and page views)
- ✅ Database changes (ActiveRecord create/update/destroy)
- ✅ Background jobs (ActiveJob and Sidekiq)
- ✅ Custom events (when you add them)

## 🎯 What Gets Tracked Automatically

After restarting your Rails application, **events are automatically captured** - no additional code needed!

### HTTP Request Events
Every web request generates an event automatically:

```json
{
  "event_type": "http.request",
  "action": "POST /orders",
  "actor": { "type": "user", "id": "user_123" },
  "subject": { "type": "endpoint", "id": "/orders" },
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "method": "POST",
    "path": "/orders",
    "status_code": 201,
    "duration_ms": 45,
    "user_agent": "Mozilla/5.0...",
    "content_type": "application/json"
  }
}
```

### Database Change Events
ActiveRecord operations are automatically tracked:

```json
{
  "event_type": "data.change",
  "action": "order.create",
  "actor": { "type": "system", "id": "system" },
  "subject": { "type": "order", "id": "order_456" },
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "model": "Order",
    "table": "orders",
    "record_id": "456",
    "action": "create",
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
  "event_type": "job.execution",
  "action": "ProcessOrderJob.completed",
  "actor": { "type": "system", "id": "system" },
  "subject": { "type": "job", "id": "ProcessOrderJob" },
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "job_name": "ProcessOrderJob",
    "job_id": "job_789",
    "status": "completed",
    "duration": 1.25,
    "queue": "default",
    "result": { "success": true }
  }
}
```

## 🔗 Perfect Correlation

All events in a single request share the same correlation ID:

```
HTTP Request → Database Change → Background Job → Sidekiq Job
     ↓              ↓                ↓              ↓
corr_abc123    corr_abc123      corr_abc123    corr_abc123
```

This means you can trace the complete journey of any request through your entire application!

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
      event_type: 'order.action',
      action: 'created',
      actor: { type: 'user', id: current_user.id },
      subject: { type: 'order', id: order.id },
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
      event_type: 'order.action',
      action: 'created',
      actor: { type: 'user', id: user_id },
      subject: { type: 'order', id: id },
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
      event_type: 'order.processing',
      action: 'started',
      actor: { type: 'system', id: 'system' },
      subject: { type: 'order', id: order_id },
      metadata: { queue: queue_name }
    )
    
    # Process the order
    order.process!
    
    # Track custom completion event (optional)
    EzlogsRubyAgent.log_event(
      event_type: 'order.processing',
      action: 'completed',
      actor: { type: 'system', id: 'system' },
      subject: { type: 'order', id: order_id },
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
    flow_id = EzlogsRubyAgent.start_flow('order_fulfillment', order_id, {
      priority: 'high',
      customer_type: 'premium'
    })
    
    # All events in this flow will share the same flow_id
    order = Order.find(order_id)
    
    # Process payment
    payment_result = process_payment(order)
    EzlogsRubyAgent.log_event(
      event_type: 'payment.processed',
      action: 'payment.success',
      actor: { type: 'system', id: 'payment_processor' },
      subject: { type: 'order', id: order_id },
      metadata: { amount: order.total, method: 'credit_card' }
    )
    
    # Update inventory
    update_inventory(order)
    EzlogsRubyAgent.log_event(
      event_type: 'inventory.updated',
      action: 'inventory.reserved',
      actor: { type: 'system', id: 'inventory_system' },
      subject: { type: 'order', id: order_id },
      metadata: { items_reserved: order.items.count }
    )
    
    # Send confirmation
    send_confirmation_email(order)
    EzlogsRubyAgent.log_event(
      event_type: 'notification.sent',
      action: 'email.order_confirmation',
      actor: { type: 'system', id: 'notification_service' },
      subject: { type: 'order', id: order_id },
      metadata: { type: 'email', template: 'order_confirmation' }
    )
    
    # Complete the flow
    EzlogsRubyAgent.complete_flow(flow_id, { success: true })
  end
end
```

## 🧪 Testing Your Setup

### Test Mode

Enable test mode to capture events in memory for testing:

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

## 🔧 Configuration Options

### Zero-Config Defaults

EZLogs Ruby Agent comes with intelligent defaults:

- **Service Name**: Auto-detected from Rails app name
- **Environment**: Auto-detected from `Rails.env`
- **All Collectors**: Enabled by default
- **Security**: PII detection enabled
- **Performance**: Optimized for production

### Basic Configuration

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

## 🚀 Next Steps

1. **Deploy to Production**: Your app is now tracking events automatically!
2. **Monitor Events**: Check your Go server logs to see events flowing
3. **Add Custom Events**: Track business-specific events as needed
4. **Configure Security**: Set up PII detection and field filtering
5. **Optimize Performance**: Adjust buffer sizes and delivery settings

## 🆘 Need Help?

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/your-org/ezlogs_ruby_agent/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/ezlogs_ruby_agent/discussions)

---

**You're all set! Your Rails app is now tracking events with perfect correlation.** 🎉 