# Basic Rails App Example

This example demonstrates the core EZLogs Ruby Agent features in a simple Rails application.

## 🚀 Quick Start

```bash
cd examples/basic_rails_app
bundle install
rails db:create db:migrate
rails server
```

Visit `http://localhost:3000` to see the application in action.

## 📊 What This Example Demonstrates

### 1. Automatic HTTP Request Tracking

Every web request is automatically tracked - no code needed:

```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def index
    @orders = Order.all
  end
  
  def create
    @order = Order.create!(order_params)
    redirect_to @order
  end
end
```

**Automatically Generated Events:**
- `http_request` events for each page load
- Request duration, status, and metadata
- Automatic actor extraction from current user

### 2. Automatic Database Change Tracking

ActiveRecord operations are tracked automatically:

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :user
  has_many :order_items
  
  validates :total, presence: true, numericality: { greater_than: 0 }
end
```

**Automatically Generated Events:**
- `database_change` events for create/update/destroy
- Field changes and record metadata
- Table and record ID information

### 3. Custom Business Events (Optional)

Track important business actions beyond automatic tracking:

```ruby
# app/controllers/orders_controller.rb
def create
  @order = Order.create!(order_params)
  
  # Track custom business event (optional)
  EzlogsRubyAgent.log_event(
    event_type: 'order',
    action: 'created',
    actor: current_user.id,
    subject: @order.id,
    metadata: {
      total: @order.total,
      items_count: @order.order_items.count,
      currency: @order.currency
    }
  )
  
  redirect_to @order
end
```

### 4. Automatic Background Job Tracking

Job execution is tracked automatically:

```ruby
# app/jobs/process_order_job.rb
class ProcessOrderJob < ApplicationJob
  queue_as :default
  
  def perform(order_id)
    order = Order.find(order_id)
    
    # Process the order
    order.update!(status: 'processed')
    
    # Send confirmation email
    OrderMailer.confirmation(order).deliver_now
  end
end
```

**Automatically Generated Events:**
- `background_job` events for job start/completion
- Job duration and queue information
- Error tracking for failed jobs

## 🔧 Configuration

### Basic Configuration

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |c|
  c.service_name = 'basic-rails-app'
  c.environment = Rails.env
  
  # Enable all tracking
  c.collect do |collect|
    collect.http_requests = true
    collect.database_changes = true
    collect.background_jobs = true
  end
  
  # Security settings
  c.security do |security|
    security.auto_detect_pii = true
    security.sanitize_fields = ['password', 'token']
  end
  
  # Performance settings
  c.performance do |perf|
    perf.sample_rate = 1.0  # 100% sampling for demo
    perf.buffer_size = 100
  end
end
```

### Development Configuration

```ruby
# config/environments/development.rb
# Enable debug mode for development
EzlogsRubyAgent.debug_mode = true
```

## 📊 Sample Events

### HTTP Request Event

```json
{
  "event_type": "http_request",
  "action": "GET",
  "actor": "user_1",
  "subject": "/orders",
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "path": "/orders",
    "method": "GET",
    "status": 200,
    "duration_ms": 45,
    "user_agent": "Mozilla/5.0...",
    "ip_address": "127.0.0.1"
  }
}
```

### Database Change Event

```json
{
  "event_type": "database_change",
  "action": "created",
  "actor": "user_1",
  "subject": "Order_123",
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "table": "orders",
    "record_id": 123,
    "changes": {
      "total": [null, 99.99],
      "status": [null, "pending"],
      "user_id": [null, 1]
    }
  }
}
```

### Custom Business Event

```json
{
  "event_type": "order",
  "action": "created",
  "actor": "user_1",
  "subject": 123,
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "total": 99.99,
    "items_count": 2,
    "currency": "USD"
  }
}
```

### Background Job Event

```json
{
  "event_type": "background_job",
  "action": "completed",
  "actor": "system",
  "subject": "ProcessOrderJob_456",
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "job_class": "ProcessOrderJob",
    "job_id": "456",
    "duration_ms": 1250,
    "queue": "default"
  }
}
```

## 🧪 Testing

### Test Configuration

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

### Sample Tests

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

## 🔍 Monitoring

### Health Check

```ruby
# Check system health
status = EzlogsRubyAgent.health_status
puts "EZLogs Health: #{status[:writer][:healthy]}"
```

### Performance Metrics

```ruby
# Get performance metrics
metrics = EzlogsRubyAgent.performance_monitor.metrics
puts "Events processed: #{metrics[:events_processed]}"
puts "Average latency: #{metrics[:avg_latency_ms]}ms"
```

## 📚 Next Steps

- **[Advanced Rails App](../advanced_rails_app/)** - More complex features
- **[E-commerce App](../ecommerce_app/)** - Real-world business logic
- **[API App](../api_app/)** - REST API tracking
- **[Microservices App](../microservices_app/)** - Distributed tracing

---

**This example shows the basics of EZLogs integration.** Explore the other examples to see more advanced features! 🚀 