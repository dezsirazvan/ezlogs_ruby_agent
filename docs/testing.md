# Testing Guide

EZLogs Ruby Agent provides comprehensive testing support to ensure your event tracking works correctly in all environments. This guide covers testing strategies, helpers, and best practices.

## 🧪 Testing Philosophy

### Test-Driven Development

EZLogs is built with testing in mind:

- **Zero-impact testing** - test without affecting your application
- **Comprehensive test helpers** - easy setup and assertions
- **Real-world scenarios** - test actual event flows
- **Performance testing** - ensure no performance regression
- **Security testing** - verify data protection

### Testing Guarantees

| Feature | Guarantee | Testing Support |
|---------|-----------|-----------------|
| **Event Capture** | 100% reliable | In-memory capture |
| **Performance** | Sub-1ms overhead | Performance tests |
| **Security** | PII protection | Security validation |
| **Thread Safety** | Concurrent safe | Thread safety tests |
| **Configuration** | Validated setup | Configuration tests |

## 🚀 Quick Testing Setup

### Basic Test Configuration

Add to your test setup:

```ruby
# spec/support/ezlogs_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    # Enable test mode for all tests
    EzlogsRubyAgent.test_mode do
      # All events are captured in memory
    end
  end
  
  config.after(:each) do
    # Clean up after each test
    EzlogsRubyAgent.clear_captured_events
  end
end
```

### Simple Event Testing

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

## 📊 Test Modes

### Test Mode

Capture events in memory for assertions:

```ruby
# Enable test mode
EzlogsRubyAgent.test_mode do
  # All events are captured in memory
  EzlogsRubyAgent.log_event(
    event_type: 'test',
    action: 'created',
    actor: 'test',
    subject: 'test'
  )
  
  # Access captured events
  events = EzlogsRubyAgent.captured_events
  expect(events.length).to eq(1)
end
```

### Debug Mode

Enable debug mode for development testing:

```ruby
# Enable debug mode
EzlogsRubyAgent.debug_mode = true

# Events are logged to console and captured
EzlogsRubyAgent.log_event(
  event_type: 'test',
  action: 'created',
  actor: 'test',
  subject: 'test'
)

# Check captured events
events = EzlogsRubyAgent.captured_events
puts "Captured #{events.length} events"
```

### Performance Test Mode

Test performance characteristics:

```ruby
# Performance testing
EzlogsRubyAgent.performance_test_mode do
  start_time = Time.current
  
  1000.times do
    EzlogsRubyAgent.log_event(
      event_type: 'test',
      action: 'created',
      actor: 'test',
      subject: 'test'
    )
  end
  
  duration = Time.current - start_time
  events_per_second = 1000 / duration
  
  expect(events_per_second).to be > 1000  # > 1000 events/sec
  expect(duration).to be < 1.0  # < 1 second for 1000 events
end
```

## 🔧 Test Helpers

### Event Assertions

Easy assertions for event testing:

```ruby
# spec/support/ezlogs_matchers.rb
RSpec::Matchers.define :have_logged_event do |event_type, action|
  match do |actual|
    events = EzlogsRubyAgent.captured_events
    events.any? do |event|
      event[:event_type] == event_type && event[:action] == action
    end
  end
  
  failure_message do |actual|
    events = EzlogsRubyAgent.captured_events
    "Expected to log #{event_type}:#{action}, but found: #{events.map { |e| "#{e[:event_type]}:#{e[:action]}" }}"
  end
end

# Usage
expect { create_order }.to have_logged_event('order', 'created')
```

### Event Count Assertions

```ruby
RSpec::Matchers.define :have_logged_events_count do |count|
  match do |actual|
    EzlogsRubyAgent.captured_events.length == count
  end
  
  failure_message do |actual|
    actual_count = EzlogsRubyAgent.captured_events.length
    "Expected #{count} events, but found #{actual_count}"
  end
end

# Usage
expect { create_multiple_orders }.to have_logged_events_count(3)
```

### Event Content Assertions

```ruby
RSpec::Matchers.define :have_logged_event_with do |event_type, action, metadata|
  match do |actual|
    events = EzlogsRubyAgent.captured_events
    events.any? do |event|
      event[:event_type] == event_type &&
      event[:action] == action &&
      metadata.all? { |key, value| event[:metadata][key] == value }
    end
  end
end

# Usage
expect { create_order }.to have_logged_event_with('order', 'created', { total: 99.99 })
```

## 📝 Testing Strategies

### Unit Testing

Test individual components:

```ruby
# spec/models/order_spec.rb
RSpec.describe Order, type: :model do
  it "tracks creation events" do
    order = Order.create!(total: 99.99)
    
    events = EzlogsRubyAgent.captured_events
    expect(events).to include(
      hash_including(
        event_type: 'database_change',
        action: 'created',
        subject: "Order_#{order.id}",
        metadata: hash_including(
          table: 'orders',
          record_id: order.id
        )
      )
    )
  end
  
  it "tracks update events" do
    order = Order.create!(total: 99.99)
    EzlogsRubyAgent.clear_captured_events
    
    order.update!(total: 149.99)
    
    events = EzlogsRubyAgent.captured_events
    expect(events).to include(
      hash_including(
        event_type: 'database_change',
        action: 'updated',
        metadata: hash_including(
          changes: hash_including('total')
        )
      )
    )
  end
end
```

### Controller Testing

Test HTTP request tracking:

```ruby
# spec/controllers/api/orders_controller_spec.rb
RSpec.describe Api::OrdersController, type: :controller do
  it "tracks API requests" do
    get :index
    
    events = EzlogsRubyAgent.captured_events
    expect(events).to include(
      hash_including(
        event_type: 'http_request',
        action: 'GET',
        subject: '/api/orders',
        metadata: hash_including(
          path: '/api/orders',
          method: 'GET',
          status: 200
        )
      )
    )
  end
  
  it "tracks request duration" do
    get :index
    
    events = EzlogsRubyAgent.captured_events
    http_event = events.find { |e| e[:event_type] == 'http_request' }
    
    expect(http_event[:metadata][:duration_ms]).to be > 0
    expect(http_event[:metadata][:duration_ms]).to be < 1000  # < 1 second
  end
  
  it "tracks error responses" do
    allow(Order).to receive(:all).and_raise(StandardError, "Database error")
    
    expect { get :index }.to raise_error(StandardError)
    
    events = EzlogsRubyAgent.captured_events
    expect(events).to include(
      hash_including(
        event_type: 'http_request',
        metadata: hash_including(
          status: 500,
          error: 'StandardError: Database error'
        )
      )
    )
  end
end
```

### Job Testing

Test background job tracking:

```ruby
# spec/jobs/process_order_job_spec.rb
RSpec.describe ProcessOrderJob, type: :job do
  it "tracks job execution" do
    order = Order.create!(total: 99.99)
    
    perform_enqueued_jobs do
      ProcessOrderJob.perform_later(order.id)
    end
    
    events = EzlogsRubyAgent.captured_events
    expect(events).to include(
      hash_including(
        event_type: 'background_job',
        action: 'started',
        subject: /ProcessOrderJob_\d+/,
        metadata: hash_including(
          job_class: 'ProcessOrderJob',
          queue: 'default'
        )
      ),
      hash_including(
        event_type: 'background_job',
        action: 'completed',
        subject: /ProcessOrderJob_\d+/,
        metadata: hash_including(
          duration_ms: be > 0
        )
      )
    )
  end
  
  it "tracks job failures" do
    order = Order.create!(total: 99.99)
    allow(Order).to receive(:find).and_raise(StandardError, "Job failed")
    
    expect {
      perform_enqueued_jobs do
        ProcessOrderJob.perform_later(order.id)
      end
    }.to raise_error(StandardError)
    
    events = EzlogsRubyAgent.captured_events
    expect(events).to include(
      hash_including(
        event_type: 'background_job',
        action: 'failed',
        metadata: hash_including(
          error: 'StandardError: Job failed'
        )
      )
    )
  end
end
```

### Integration Testing

Test complete workflows:

```ruby
# spec/integration/order_workflow_spec.rb
RSpec.describe "Order Workflow", type: :integration do
  it "tracks complete order lifecycle" do
    # Create order
    post "/api/orders", params: { order: { total: 99.99 } }
    order_id = JSON.parse(response.body)["id"]
    
    # Process payment
    post "/api/orders/#{order_id}/pay", params: { payment_method: "credit_card" }
    
    # Fulfill order
    post "/api/orders/#{order_id}/fulfill"
    
    events = EzlogsRubyAgent.captured_events
    
    # Verify HTTP requests
    expect(events).to include(
      hash_including(event_type: 'http_request', action: 'POST', subject: '/api/orders'),
      hash_including(event_type: 'http_request', action: 'POST', subject: "/api/orders/#{order_id}/pay"),
      hash_including(event_type: 'http_request', action: 'POST', subject: "/api/orders/#{order_id}/fulfill")
    )
    
    # Verify database changes
    expect(events).to include(
      hash_including(event_type: 'database_change', action: 'created', subject: "Order_#{order_id}"),
      hash_including(event_type: 'database_change', action: 'updated', subject: "Order_#{order_id}")
    )
    
    # Verify custom events
    expect(events).to include(
      hash_including(event_type: 'order', action: 'created'),
      hash_including(event_type: 'payment', action: 'processed'),
      hash_including(event_type: 'order', action: 'fulfilled')
    )
  end
end
```

## 🔍 Advanced Testing

### Correlation Testing

Test business flow tracking:

```ruby
# spec/integration/correlation_spec.rb
RSpec.describe "Event Correlation", type: :integration do
  it "tracks correlated events" do
    order_id = "order_123"
    
    # Start a business flow
    EzlogsRubyAgent.start_flow('order_fulfillment', order_id, {
      customer_id: 'customer_456',
      priority: 'high'
    })
    
    # Log correlated events
    EzlogsRubyAgent.log_event(
      event_type: 'inventory',
      action: 'reserved',
      subject: order_id
    )
    
    EzlogsRubyAgent.log_event(
      event_type: 'shipping',
      action: 'label_created',
      subject: order_id
    )
    
    events = EzlogsRubyAgent.captured_events
    
    # All events should have the same correlation ID
    correlation_ids = events.map { |e| e[:correlation_id] }.compact.uniq
    expect(correlation_ids.length).to eq(1)
    
    # Verify flow context
    flow_events = events.select { |e| e[:event_type] == 'flow_started' }
    expect(flow_events).to include(
      hash_including(
        event_type: 'flow_started',
        subject: order_id,
        metadata: hash_including(
          flow_type: 'order_fulfillment',
          customer_id: 'customer_456',
          priority: 'high'
        )
      )
    )
  end
end
```

### Performance Testing

Test performance characteristics:

```ruby
# spec/performance/ezlogs_performance_spec.rb
RSpec.describe "EZLogs Performance", type: :performance do
  it "creates events quickly" do
    start_time = Time.current
    
    1000.times do
      EzlogsRubyAgent.log_event(
        event_type: 'test',
        action: 'created',
        actor: 'test',
        subject: 'test'
      )
    end
    
    duration = Time.current - start_time
    events_per_second = 1000 / duration
    
    expect(events_per_second).to be > 1000  # > 1000 events/sec
    expect(duration).to be < 1.0  # < 1 second for 1000 events
  end
  
  it "uses minimal memory" do
    initial_memory = GC.stat[:total_allocated_objects]
    
    1000.times do
      EzlogsRubyAgent.log_event(
        event_type: 'test',
        action: 'created',
        actor: 'test',
        subject: 'test'
      )
    end
    
    final_memory = GC.stat[:total_allocated_objects]
    memory_increase = final_memory - initial_memory
    
    expect(memory_increase).to be < 10000  # < 10k objects
  end
  
  it "handles concurrent access" do
    threads = []
    events_per_thread = 100
    
    10.times do
      threads << Thread.new do
        events_per_thread.times do
          EzlogsRubyAgent.log_event(
            event_type: 'test',
            action: 'created',
            actor: 'test',
            subject: 'test'
          )
        end
      end
    end
    
    threads.each(&:join)
    
    total_events = EzlogsRubyAgent.captured_events.length
    expect(total_events).to eq(10 * events_per_thread)
  end
end
```

### Security Testing

Test security features:

```ruby
# spec/security/ezlogs_security_spec.rb
RSpec.describe "EZLogs Security", type: :security do
  it "sanitizes PII fields" do
    EzlogsRubyAgent.log_event(
      event_type: 'user',
      action: 'created',
      actor: 'system',
      subject: 'user_123',
      metadata: {
        email: 'john@example.com',
        password: 'secret123',
        ssn: '123-45-6789'
      }
    )
    
    events = EzlogsRubyAgent.captured_events
    event = events.last
    
    expect(event[:metadata][:email]).to eq('***@example.com')
    expect(event[:metadata][:password]).to eq('*********')
    expect(event[:metadata][:ssn]).to eq('***-**-6789')
  end
  
  it "rejects oversized payloads" do
    large_metadata = { data: 'x' * (1024 * 1024 + 1) }  # > 1MB
    
    expect {
      EzlogsRubyAgent.log_event(
        event_type: 'test',
        action: 'created',
        actor: 'test',
        subject: 'test',
        metadata: large_metadata
      )
    }.to raise_error(EzlogsRubyAgent::SecurityError, /Payload too large/)
  end
  
  it "excludes sensitive fields" do
    EzlogsRubyAgent.log_event(
      event_type: 'user',
      action: 'created',
      actor: 'system',
      subject: 'user_123',
      metadata: {
        id: 123,
        name: 'John Doe',
        password: 'secret123',
        private_key: 'abc123'
      }
    )
    
    events = EzlogsRubyAgent.captured_events
    event = events.last
    
    expect(event[:metadata]).to include('id', 'name')
    expect(event[:metadata]).not_to include('password', 'private_key')
  end
end
```

## 🔧 Test Configuration

### Environment-Specific Testing

```ruby
# spec/support/ezlogs_test_config.rb
RSpec.configure do |config|
  config.before(:suite) do
    # Configure EZLogs for testing
    EzlogsRubyAgent.configure do |c|
      c.service_name = 'test-app'
      c.environment = 'test'
      
      # Disable actual delivery in tests
      c.delivery do |delivery|
        delivery.endpoint = nil
      end
      
      # Enable test mode
      c.test_mode = true
    end
  end
end
```

### Custom Test Helpers

```ruby
# spec/support/ezlogs_test_helpers.rb
module EzlogsTestHelpers
  def capture_events
    EzlogsRubyAgent.clear_captured_events
    yield
    EzlogsRubyAgent.captured_events
  end
  
  def assert_event_logged(event_type, action, metadata = {})
    events = EzlogsRubyAgent.captured_events
    matching_events = events.select do |event|
      event[:event_type] == event_type &&
      event[:action] == action &&
      metadata.all? { |key, value| event[:metadata][key] == value }
    end
    
    expect(matching_events).not_to be_empty
  end
  
  def assert_no_events_logged
    expect(EzlogsRubyAgent.captured_events).to be_empty
  end
end

RSpec.configure do |config|
  config.include EzlogsTestHelpers
end
```

## 📊 Test Data Management

### Event Factories

```ruby
# spec/factories/ezlogs_events.rb
FactoryBot.define do
  factory :ezlogs_event, class: Hash do
    event_type { 'test' }
    action { 'created' }
    actor { 'test_user' }
    subject { 'test_subject' }
    metadata { {} }
    timestamp { Time.current }
    
    initialize_with { attributes }
  end
  
  factory :order_event, parent: :ezlogs_event do
    event_type { 'order' }
    action { 'created' }
    metadata { { total: 99.99, currency: 'USD' } }
  end
  
  factory :user_event, parent: :ezlogs_event do
    event_type { 'user' }
    action { 'registered' }
    metadata { { email: 'test@example.com', plan: 'premium' } }
  end
end
```

### Test Data Cleanup

```ruby
# spec/support/ezlogs_cleanup.rb
RSpec.configure do |config|
  config.before(:each) do
    # Clear captured events before each test
    EzlogsRubyAgent.clear_captured_events
  end
  
  config.after(:each) do
    # Verify no events leaked between tests
    expect(EzlogsRubyAgent.captured_events).to be_empty
  end
  
  config.after(:suite) do
    # Clean up any remaining test data
    EzlogsRubyAgent.shutdown
  end
end
```

## 🚨 Testing Best Practices

### Test Organization

1. **Group related tests** by feature or component
2. **Use descriptive test names** that explain the behavior
3. **Test both success and failure scenarios**
4. **Test edge cases** and boundary conditions

### Test Performance

1. **Use test mode** to avoid network calls
2. **Clear events between tests** to prevent interference
3. **Mock external dependencies** when testing
4. **Use factories** for consistent test data

### Test Coverage

1. **Test all event types** (HTTP, database, jobs, custom)
2. **Test configuration options** and their effects
3. **Test security features** thoroughly
4. **Test performance characteristics** regularly

### Test Maintenance

1. **Keep tests focused** on single behaviors
2. **Update tests** when API changes
3. **Review test failures** carefully
4. **Document test patterns** for team consistency

## 📚 Next Steps

- **[Configuration Guide](configuration.md)** - Complete configuration options
- **[Performance Guide](performance.md)** - Optimization and tuning
- **[Security Guide](security.md)** - Security best practices
- **[API Reference](../lib/ezlogs_ruby_agent.rb)** - Complete API documentation
- **[Examples](../examples/)** - Complete example applications

---

**Testing is the foundation of reliable event tracking.** Use these guidelines to ensure your EZLogs implementation works correctly in all scenarios! 🧪 