# Security Guide

EZLogs Ruby Agent is designed with security-first principles to protect sensitive data and ensure compliance with privacy regulations.

## 🔒 Security Features

### Automatic PII Detection

EZLogs Ruby Agent automatically detects and sanitizes Personally Identifiable Information (PII):

- **Email addresses**: `user@example.com`
- **Phone numbers**: `+1-555-123-4567`
- **Social Security Numbers**: `123-45-6789`
- **Credit card numbers**: `4111-1111-1111-1111`
- **IP addresses**: `192.168.1.100`
- **Custom patterns**: Configurable regex patterns

### Zero-Config Security

Security features are enabled by default:

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |config|
  # Security is enabled by default
  # No additional configuration needed
end
```

## 🛡️ PII Protection

### Automatic Detection

EZLogs Ruby Agent automatically detects common PII patterns:

```ruby
# These will be automatically detected and sanitized
EzlogsRubyAgent.log_event(
  event_type: 'user.action',
  action: 'profile_updated',
  actor: { type: 'user', id: '123' },
  metadata: {
    email: 'user@example.com',           # → [REDACTED]
    phone: '+1-555-123-4567',            # → [REDACTED]
    ssn: '123-45-6789',                  # → [REDACTED]
    credit_card: '4111-1111-1111-1111'   # → [REDACTED]
  }
)
```

### Custom PII Patterns

Define custom patterns for your domain-specific sensitive data:

```ruby
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    security.auto_detect_pii = true
    security.custom_pii_patterns = {
      'employee_id' => /\bEMP-\d{6}\b/,
      'customer_id' => /\bCUST-\d{8}\b/,
      'api_key' => /\b[A-Za-z0-9]{32}\b/,
      'license_plate' => /\b[A-Z]{3}-\d{3}\b/
    }
  end
end
```

### Sensitive Field Filtering

Explicitly mark fields as sensitive:

```ruby
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    security.sensitive_fields = [
      'password',
      'token',
      'api_key',
      'secret',
      'private_key',
      'session_id',
      'auth_token'
    ]
  end
end
```

## 🔐 Field Filtering

### Include-Only Filtering

Only track specific resources and fields:

```ruby
EzlogsRubyAgent.configure do |config|
  # Only track these resources
  config.included_resources = ['order', 'user', 'payment']
  
  # Only include these fields in metadata
  config.included_fields = ['id', 'status', 'amount', 'created_at']
end
```

### Exclude Filtering

Exclude sensitive resources and fields:

```ruby
EzlogsRubyAgent.configure do |config|
  # Exclude these resources entirely
  config.excluded_resources = [
    'temp',
    'cache',
    'session',
    'password_reset',
    'admin_log'
  ]
  
  # Exclude these fields from all events
  config.excluded_fields = [
    'password',
    'token',
    'secret',
    'private_data'
  ]
end
```

## 📏 Size Limits

### Event Size Limits

Prevent oversized events that could impact performance:

```ruby
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    # Maximum event size (1MB)
    security.max_event_size = 1024 * 1024
    
    # Maximum field value size (1KB)
    security.max_field_size = 1024
    
    # Maximum number of fields per event
    security.max_fields_per_event = 100
  end
end
```

### Payload Validation

Events exceeding limits are automatically truncated or rejected:

```ruby
# This event would be truncated if it exceeds limits
EzlogsRubyAgent.log_event(
  event_type: 'data.export',
  action: 'completed',
  actor: { type: 'user', id: '123' },
  metadata: {
    # Large data will be truncated to max_field_size
    export_data: very_large_data_object
  }
)
```

## 🔍 Sanitization Methods

### Default Sanitization

By default, sensitive data is replaced with `[REDACTED]`:

```ruby
# Input
metadata: { email: 'user@example.com', phone: '+1-555-123-4567' }

# Output
metadata: { email: '[REDACTED]', phone: '[REDACTED]' }
```

### Custom Sanitization

Configure custom sanitization methods:

```ruby
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    # Custom sanitization function
    security.sanitization_method = ->(value, field_name) do
      case field_name
      when 'email'
        # Mask email: user@example.com → u***@example.com
        parts = value.split('@')
        "#{parts[0][0]}***@#{parts[1]}"
      when 'phone'
        # Mask phone: +1-555-123-4567 → +1-555-***-4567
        value.gsub(/(\+\d{1,3}-\d{3}-)\d{3}(-\d{4})/, '\1***\2')
      else
        '[REDACTED]'
      end
    end
  end
end
```

## 🚫 Data Exclusion

### Complete Resource Exclusion

Exclude entire resources from tracking:

```ruby
EzlogsRubyAgent.configure do |config|
  # Never track these models
  config.excluded_resources = [
    'UserSession',
    'PasswordReset',
    'AdminAuditLog',
    'SensitiveData'
  ]
end
```

### Conditional Exclusion

Exclude data based on conditions:

```ruby
# In your models
class User < ApplicationRecord
  after_create :track_user_creation
  
  private
  
  def track_user_creation
    # Only track non-sensitive user creation
    return if sensitive_user?
    
    EzlogsRubyAgent.log_event(
      event_type: 'user.action',
      action: 'created',
      actor: { type: 'system', id: 'system' },
      subject: { type: 'user', id: id },
      metadata: {
        role: role,
        status: status
        # Sensitive fields like email, password are excluded
      }
    )
  end
  
  def sensitive_user?
    role == 'admin' || email.include?('sensitive')
  end
end
```

## 🔒 Environment-Specific Security

### Development Environment

```ruby
# config/environments/development.rb
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    # More permissive in development
    security.auto_detect_pii = false
    security.max_event_size = 2 * 1024 * 1024  # 2MB
  end
  
  # Enable debug mode to see what's being sanitized
  config.debug_mode = true
end
```

### Production Environment

```ruby
# config/environments/production.rb
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    # Strict security in production
    security.auto_detect_pii = true
    security.max_event_size = 1024 * 1024  # 1MB
    security.sensitive_fields = [
      'password', 'token', 'api_key', 'secret', 'ssn',
      'credit_card', 'private_key', 'session_data'
    ]
  end
  
  # Disable debug mode
  config.debug_mode = false
end
```

## 🧪 Security Testing

### Test Mode Security

Test security features without sending data:

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

### Security Validation Tests

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

## 🔍 Security Monitoring

### Security Event Logging

Monitor security-related events:

```ruby
# Log when sensitive data is detected
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    security.log_sanitization_events = true
    security.log_excluded_resources = true
  end
end
```

### Security Metrics

Track security metrics:

```ruby
# Get security statistics
security_stats = EzlogsRubyAgent.security_stats
puts "PII Detections: #{security_stats[:pii_detections]}"
puts "Sanitized Events: #{security_stats[:sanitized_events]}"
puts "Excluded Resources: #{security_stats[:excluded_resources]}"
puts "Oversized Events: #{security_stats[:oversized_events]}"
```

## 🚨 Security Best Practices

### 1. Always Enable PII Detection

```ruby
# Always enable in production
config.security.auto_detect_pii = true
```

### 2. Use Environment Variables for Secrets

```ruby
# Never hardcode sensitive values
config.delivery.headers = {
  'X-API-Key' => ENV['EZLOGS_API_KEY']
}
```

### 3. Regular Security Audits

```ruby
# Regular security checks
def audit_security_configuration
  config = EzlogsRubyAgent.config.security
  
  puts "PII Detection: #{config.auto_detect_pii}"
  puts "Sensitive Fields: #{config.sensitive_fields}"
  puts "Max Event Size: #{config.max_event_size}"
  puts "Excluded Resources: #{config.excluded_resources}"
end
```

### 4. Monitor for Security Issues

```ruby
# Alert on security concerns
def monitor_security_events
  security_stats = EzlogsRubyAgent.security_stats
  
  if security_stats[:pii_detections] > 100
    alert_team("High PII detection rate detected")
  end
  
  if security_stats[:oversized_events] > 10
    alert_team("Multiple oversized events detected")
  end
end
```

## 📋 Compliance

### GDPR Compliance

EZLogs Ruby Agent helps with GDPR compliance:

- **Data Minimization**: Only collect necessary data
- **PII Protection**: Automatic detection and sanitization
- **Data Retention**: Events are delivered immediately, not stored
- **Right to be Forgotten**: No persistent storage in the agent

### HIPAA Compliance

For healthcare applications:

```ruby
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    # HIPAA-specific patterns
    security.custom_pii_patterns = {
      'patient_id' => /\bPAT-\d{8}\b/,
      'medical_record' => /\bMRN-\d{10}\b/,
      'insurance_id' => /\bINS-\d{12}\b/
    }
    
    # Exclude all healthcare-related models
    config.excluded_resources = [
      'Patient', 'MedicalRecord', 'Insurance', 'Diagnosis'
    ]
  end
end
```

### PCI DSS Compliance

For payment processing:

```ruby
EzlogsRubyAgent.configure do |config|
  config.security do |security|
    # PCI-specific patterns
    security.custom_pii_patterns = {
      'card_number' => /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
      'cvv' => /\b\d{3,4}\b/,
      'expiry' => /\b\d{2}\/\d{2,4}\b/
    }
    
    # Exclude payment models
    config.excluded_resources = [
      'Payment', 'CreditCard', 'Transaction'
    ]
  end
end
```

## 🔧 Security Configuration Examples

### Complete Security Configuration

```ruby
# config/initializers/ezlogs_ruby_agent.rb
EzlogsRubyAgent.configure do |config|
  # Security settings
  config.security do |security|
    security.auto_detect_pii = true
    security.sensitive_fields = [
      'password', 'token', 'api_key', 'secret', 'ssn',
      'credit_card', 'private_key', 'session_data'
    ]
    security.max_event_size = 1024 * 1024  # 1MB
    security.max_field_size = 1024  # 1KB
    security.max_fields_per_event = 100
    security.custom_pii_patterns = {
      'employee_id' => /\bEMP-\d{6}\b/,
      'customer_id' => /\bCUST-\d{8}\b/
    }
    security.log_sanitization_events = true
  end
  
  # Resource filtering
  config.included_resources = ['order', 'user', 'payment']
  config.excluded_resources = [
    'temp', 'cache', 'session', 'password_reset',
    'admin_log', 'sensitive_data'
  ]
  
  # Environment-specific overrides
  if Rails.env.development?
    config.security.auto_detect_pii = false
    config.debug_mode = true
  end
end
```

## 📚 Next Steps

- **[Getting Started](getting-started.md)** - Basic setup and usage
- **[Configuration Guide](configuration.md)** - Advanced configuration options
- **[Performance Guide](performance.md)** - Optimization and tuning
- **[API Reference](../lib/ezlogs_ruby_agent.rb)** - Complete API documentation

---

**Your EZLogs Ruby Agent is now configured with enterprise-grade security!** 🔒 