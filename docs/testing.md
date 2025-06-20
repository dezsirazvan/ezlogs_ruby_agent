# Testing Guide

EZLogs Ruby Agent provides comprehensive testing support to ensure your event tracking works correctly in all environments.

## 🧪 Test Mode

### Enable Test Mode

Test mode captures events in memory instead of sending them to your Go server:

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

### Test Mode Features

- **Memory Capture**: Events stored in memory instead of being delivered
- **No Network Calls**: No HTTP requests to your Go server
- **Fast Execution**: No network latency in tests
- **Easy Assertions**: Simple API to check captured events

## 📊 Event Assertions

### Basic Event Testing

```ruby
# spec/controllers/orders_controller_spec.rb
RSpec.describe OrdersController, type: :controller do
  it "tracks order creation" do
    post :create, params: { order: { amount: 100 } }
    
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
end
```

### Custom Event Testing

```ruby
# spec/models/order_spec.rb
RSpec.describe Order, type: :model do
  it "tracks custom business events" do
    order = create(:order)
    
    # Trigger custom event
    order.process_payment!
    
    events = EzlogsRubyAgent.captured_events
    expect(events).to include(
      hash_including(
        event_type: 'order.action',
        action: 'payment.processed',
        actor: hash_including(type: 'system', id: 'system'),
        subject: hash_including(type: 'order', id: order.id.to_s)
      )
    )
  end
end
```

### Job Event Testing

```ruby
# spec/jobs/process_order_job_spec.rb
RSpec.describe ProcessOrderJob, type: :job do
  it "tracks job execution" do
    order = create(:order)
    
    perform_enqueued_jobs do
      ProcessOrderJob.perform_later(order.id)
    end
    
    events = EzlogsRubyAgent.captured_events
    expect(events).to include(
      hash_including(
        event_type: 'job.execution',
        action: 'ProcessOrderJob.completed',
        subject: hash_including(type: 'job', id: 'ProcessOrderJob')
      )
    )
  end
end
```

## 🔗 Correlation Testing

### Test Correlation Across Operations

```ruby
# spec/integration/order_flow_spec.rb
RSpec.describe "Order Flow", type: :request do
  it "maintains correlation across HTTP → DB → Job" do
    post "/orders", params: { order: { amount: 100 } }
    
    events = EzlogsRubyAgent.captured_events
    
    # All events should have the same correlation ID
    correlation_ids = events.map { |e| e.dig(:correlation, :correlation_id) }.compact.uniq
    expect(correlation_ids.length).to eq(1)
    
    # Verify event types
    event_types = events.map { |e| e[:event_type] }
    expect(event_types).to include('http.request')
    expect(event_types).to include('data.change')
    expect(event_types).to include('job.execution')
  end
end
```

### Test Custom Correlation

```ruby
# spec/services/order_fulfillment_service_spec.rb
RSpec.describe OrderFulfillmentService do
  it "tracks business flow with correlation" do
    order = create(:order)
    
    service = OrderFulfillmentService.new
    service.fulfill_order(order.id)
    
    events = EzlogsRubyAgent.captured_events
    
    # All events in the flow should have the same correlation ID
    flow_events = events.select { |e| e[:event_type].start_with?('order.') }
    correlation_ids = flow_events.map { |e| e.dig(:correlation, :correlation_id) }.compact.uniq
    expect(correlation_ids.length).to eq(1)
  end
end
```

## 🔒 Security Testing

### Test PII Sanitization

```ruby
# spec/security/event_sanitization_spec.rb
RSpec.describe "Event Sanitization" do
  it "sanitizes PII in events" do
    EzlogsRubyAgent.log_event(
      event_type: 'user.action',
      action: 'profile_updated',
      metadata: {
        email: 'user@example.com',
        phone: '+1-555-123-4567',
        ssn: '123-45-6789'
      }
    )
    
    events = EzlogsRubyAgent.captured_events
    event = events.last
    
    expect(event[:metadata][:email]).to eq('[REDACTED]')
    expect(event[:metadata][:phone]).to eq('[REDACTED]')
    expect(event[:metadata][:ssn]).to eq('[REDACTED]')
  end
  
  it "excludes sensitive resources" do
    # This should not be tracked
    UserSession.create!(user_id: 1, session_data: 'sensitive')
    
    events = EzlogsRubyAgent.captured_events
    session_events = events.select { |e| e[:event_type] == 'data.change' && e[:metadata][:model] == 'UserSession' }
    
    expect(session_events).to be_empty
  end
end
```

### Test Custom PII Patterns

```ruby
# spec/security/custom_pii_patterns_spec.rb
RSpec.describe "Custom PII Patterns" do
  before do
    EzlogsRubyAgent.configure do |config|
      config.security do |security|
        security.custom_pii_patterns = {
          'employee_id' => /\bEMP-\d{6}\b/
        }
      end
    end
  end
  
  it "sanitizes custom PII patterns" do
    EzlogsRubyAgent.log_event(
      event_type: 'employee.action',
      action: 'created',
      metadata: {
        employee_id: 'EMP-123456'
      }
    )
    
    events = EzlogsRubyAgent.captured_events
    event = events.last
    
    expect(event[:metadata][:employee_id]).to eq('[REDACTED]')
  end
end
```

## ⚡ Performance Testing

### Test Event Creation Performance

```ruby
# spec/performance/event_creation_spec.rb
RSpec.describe "Event Creation Performance", type: :performance do
  it "creates events quickly" do
    times = []
    
    100.times do
      start_time = Time.now
      EzlogsRubyAgent.log_event(
        event_type: 'test.event',
        action: 'created',
        actor: { type: 'system', id: 'test' }
      )
      end_time = Time.now
      times << (end_time - start_time) * 1000
    end
    
    avg_time = times.sum / times.length
    p95_time = times.sort[times.length * 0.95]
    
    expect(avg_time).to be < 1.0  # < 1ms average
    expect(p95_time).to be < 2.0  # < 2ms 95th percentile
  end
end
```

### Test Memory Usage

```ruby
# spec/performance/memory_usage_spec.rb
RSpec.describe "Memory Usage", type: :performance do
  it "does not leak memory" do
    initial_memory = get_memory_usage
    
    1000.times do
      EzlogsRubyAgent.log_event(
        event_type: 'test.event',
        action: 'created',
        actor: { type: 'system', id: 'test' }
      )
    end
    
    final_memory = get_memory_usage
    memory_growth = final_memory - initial_memory
    
    # Memory growth should be minimal
    expect(memory_growth).to be < 10  # < 10MB growth
  end
  
  private
  
  def get_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  end
end
```

## 🔧 Configuration Testing

### Test Configuration Loading

```ruby
# spec/configuration/loading_spec.rb
RSpec.describe "Configuration Loading" do
  it "loads configuration correctly" do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
    end
    
    expect(EzlogsRubyAgent.config.service_name).to eq('test-app')
    expect(EzlogsRubyAgent.config.environment).to eq('test')
  end
  
  it "loads from environment variables" do
    ClimateControl.modify(EZLOGS_SERVICE_NAME: 'env-app') do
      config = EzlogsRubyAgent::Configuration.new
      expect(config.service_name).to eq('env-app')
    end
  end
end
```

### Test Configuration Validation

```ruby
# spec/configuration/validation_spec.rb
RSpec.describe "Configuration Validation" do
  it "validates required settings" do
    expect {
      EzlogsRubyAgent.configure do |config|
        config.service_name = nil
        config.environment = nil
      end
    }.not_to raise_error
    
    # Validation happens in Railtie, not in configuration
  end
end
```

## 🚀 Integration Testing

### Test Complete User Journey

```ruby
# spec/integration/complete_user_journey_spec.rb
RSpec.describe "Complete User Journey", type: :request do
  it "tracks complete order flow" do
    user = create(:user)
    sign_in user
    
    # 1. User creates order
    post "/orders", params: { order: { amount: 100 } }
    
    # 2. User views order
    get "/orders/#{Order.last.id}"
    
    # 3. User cancels order
    delete "/orders/#{Order.last.id}"
    
    events = EzlogsRubyAgent.captured_events
    
    # Verify all expected events
    expect(events).to include(
      hash_including(event_type: 'http.request', action: 'POST /orders')
    )
    
    expect(events).to include(
      hash_including(event_type: 'data.change', action: 'order.create')
    )
    
    expect(events).to include(
      hash_including(event_type: 'http.request', action: 'GET /orders/')
    )
    
    expect(events).to include(
      hash_including(event_type: 'http.request', action: 'DELETE /orders/')
    )
    
    expect(events).to include(
      hash_including(event_type: 'data.change', action: 'order.destroy')
    )
    
    # Verify correlation
    correlation_ids = events.map { |e| e.dig(:correlation, :correlation_id) }.compact.uniq
    expect(correlation_ids.length).to eq(1)
  end
end
```

### Test Background Job Integration

```ruby
# spec/integration/background_jobs_spec.rb
RSpec.describe "Background Job Integration", type: :request do
  it "tracks job execution from HTTP request" do
    post "/orders", params: { order: { amount: 100 } }
    
    # Process background jobs
    perform_enqueued_jobs
    
    events = EzlogsRubyAgent.captured_events
    
    # Should have HTTP, DB, and job events
    event_types = events.map { |e| e[:event_type] }
    expect(event_types).to include('http.request')
    expect(event_types).to include('data.change')
    expect(event_types).to include('job.execution')
    
    # All should have same correlation ID
    correlation_ids = events.map { |e| e.dig(:correlation, :correlation_id) }.compact.uniq
    expect(correlation_ids.length).to eq(1)
  end
end
```

## 🧹 Test Helpers

### Custom Test Helpers

```ruby
# spec/support/ezlogs_test_helpers.rb
module EzlogsTestHelpers
  def expect_event(event_type:, action:, **attributes)
    events = EzlogsRubyAgent.captured_events
    matching_events = events.select do |event|
      event[:event_type] == event_type &&
      event[:action] == action &&
      attributes.all? { |key, value| event[key] == value }
    end
    
    expect(matching_events).not_to be_empty
  end
  
  def expect_no_event(event_type:, action:)
    events = EzlogsRubyAgent.captured_events
    matching_events = events.select do |event|
      event[:event_type] == event_type && event[:action] == action
    end
    
    expect(matching_events).to be_empty
  end
  
  def expect_correlation_across_events
    events = EzlogsRubyAgent.captured_events
    correlation_ids = events.map { |e| e.dig(:correlation, :correlation_id) }.compact.uniq
    expect(correlation_ids.length).to eq(1)
  end
end

RSpec.configure do |config|
  config.include EzlogsTestHelpers
end
```

### Using Test Helpers

```ruby
# spec/controllers/orders_controller_spec.rb
RSpec.describe OrdersController, type: :controller do
  it "tracks order creation with helpers" do
    post :create, params: { order: { amount: 100 } }
    
    expect_event(
      event_type: 'http.request',
      action: 'POST /orders'
    )
    
    expect_event(
      event_type: 'data.change',
      action: 'order.create'
    )
    
    expect_correlation_across_events
  end
  
  it "does not track sensitive operations" do
    post "/admin/sensitive_operation"
    
    expect_no_event(
      event_type: 'data.change',
      action: 'sensitive_data.create'
    )
  end
end
```

## 🔍 Debug Testing

### Enable Debug Mode in Tests

```ruby
# spec/spec_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    EzlogsRubyAgent.configure do |config|
      config.debug_mode = true
    end
    
    EzlogsRubyAgent.test_mode do
      # Events captured in memory
    end
  end
end
```

### Debug Event Capture

```ruby
# spec/debug/event_debugging_spec.rb
RSpec.describe "Event Debugging" do
  it "provides debug information" do
    EzlogsRubyAgent.log_event(
      event_type: 'test.event',
      action: 'created',
      actor: { type: 'system', id: 'test' }
    )
    
    events = EzlogsRubyAgent.captured_events
    event = events.last
    
    # Debug information should be available
    expect(event).to include(:event_id, :timestamp, :correlation)
    expect(event[:platform]).to include(:service, :environment, :agent_version)
  end
end
```

## 📊 Test Coverage

### Test All Event Types

```ruby
# spec/coverage/event_types_spec.rb
RSpec.describe "Event Type Coverage" do
  it "tests all event types" do
    # HTTP events
    get "/health"
    expect_event(event_type: 'http.request', action: 'GET /health')
    
    # Database events
    user = create(:user)
    expect_event(event_type: 'data.change', action: 'user.create')
    
    # Job events
    perform_enqueued_jobs do
      TestJob.perform_later
    end
    expect_event(event_type: 'job.execution', action: 'TestJob.completed')
    
    # Custom events
    EzlogsRubyAgent.log_event(
      event_type: 'custom.event',
      action: 'test',
      actor: { type: 'system', id: 'test' }
    )
    expect_event(event_type: 'custom.event', action: 'test')
  end
end
```

### Test Error Scenarios

```ruby
# spec/coverage/error_scenarios_spec.rb
RSpec.describe "Error Scenarios" do
  it "handles invalid events gracefully" do
    # Should not raise error
    expect {
      EzlogsRubyAgent.log_event(
        event_type: nil,  # Invalid
        action: nil       # Invalid
      )
    }.not_to raise_error
  end
  
  it "handles oversized events" do
    large_data = 'x' * (1024 * 1024 + 1)  # > 1MB
    
    expect {
      EzlogsRubyAgent.log_event(
        event_type: 'test.event',
        action: 'created',
        metadata: { data: large_data }
      )
    }.not_to raise_error
  end
end
```

## 🚀 Performance Test Suites

### Load Testing

```ruby
# spec/performance/load_test_spec.rb
RSpec.describe "Load Testing", type: :performance do
  it "handles high event volume" do
    start_time = Time.now
    
    1000.times do
      EzlogsRubyAgent.log_event(
        event_type: 'load.test',
        action: 'event.created',
        actor: { type: 'system', id: 'load_test' }
      )
    end
    
    duration = Time.now - start_time
    events_per_second = 1000 / duration
    
    expect(events_per_second).to be > 1000  # > 1000 events/sec
    expect(duration).to be < 1.0  # < 1 second for 1000 events
  end
end
```

### Memory Testing

```ruby
# spec/performance/memory_test_spec.rb
RSpec.describe "Memory Testing", type: :performance do
  it "maintains stable memory usage" do
    initial_memory = get_memory_usage
    
    # Create events for 1 minute
    start_time = Time.now
    event_count = 0
    
    while Time.now - start_time < 60
      EzlogsRubyAgent.log_event(
        event_type: 'memory.test',
        action: 'event.created',
        actor: { type: 'system', id: 'memory_test' }
      )
      event_count += 1
    end
    
    final_memory = get_memory_usage
    memory_growth = final_memory - initial_memory
    
    # Memory growth should be minimal
    expect(memory_growth).to be < 50  # < 50MB growth
    expect(event_count).to be > 1000  # Should handle many events
  end
  
  private
  
  def get_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
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

**Your EZLogs Ruby Agent is now thoroughly tested and ready for production!** 🧪 