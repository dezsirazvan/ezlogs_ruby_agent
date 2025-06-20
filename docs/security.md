# Security Guide

Security is paramount when tracking application events. EZLogs Ruby Agent provides comprehensive security features to protect sensitive data and ensure compliance with privacy regulations.

## 🛡️ Security Philosophy

### Privacy by Design

EZLogs is built with these security principles:

- **Automatic PII detection** - identifies sensitive data automatically
- **Configurable sanitization** - flexible data protection strategies
- **Zero sensitive data by default** - opt-in approach to data collection
- **Compliance ready** - GDPR, CCPA, and other privacy regulations
- **Audit trail** - track what data is being collected and processed

### Security Guarantees

| Feature | Guarantee | Implementation |
|---------|-----------|----------------|
| **PII Detection** | Automatic identification | Regex patterns + ML models |
| **Data Sanitization** | Configurable protection | Masking, removal, hashing |
| **Payload Limits** | Size restrictions | Configurable limits |
| **Field Filtering** | Selective collection | Whitelist/blacklist |
| **Encryption** | TLS in transit | HTTPS delivery |
| **Access Control** | API key authentication | Secure credentials |

## 🔍 PII Detection & Protection

### Automatic PII Detection

EZLogs automatically detects common types of personally identifiable information:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    # Enable automatic PII detection
    security.auto_detect_pii = true
  end
end
```

**Automatically Detected PII Types:**
- Email addresses
- Phone numbers
- Social Security Numbers (US)
- Credit card numbers
- IP addresses
- MAC addresses
- API keys and tokens
- Passwords and secrets

### Custom PII Patterns

Define custom patterns for your specific data types:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    security.custom_patterns = {
      # Custom API key pattern
      'api_key' => /\b[A-Za-z0-9]{32}\b/,
      
      # Custom phone number pattern
      'phone' => /\b\d{3}-\d{3}-\d{4}\b/,
      
      # Custom employee ID pattern
      'employee_id' => /\bEMP-\d{6}\b/,
      
      # Custom license plate pattern
      'license_plate' => /\b[A-Z]{3}-\d{3}\b/,
      
      # Custom account number pattern
      'account_number' => /\bACC-\d{8}-\d{4}\b/
    }
  end
end
```

### Manual Field Sanitization

Explicitly specify fields to sanitize:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    security.sanitize_fields = [
      'password',
      'token',
      'secret',
      'api_key',
      'private_key',
      'ssn',
      'credit_card',
      'email',
      'phone',
      'address',
      'date_of_birth'
    ]
  end
end
```

## 🎭 Data Sanitization Methods

### Masking (Default)

Replace sensitive data with asterisks:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    security.sanitization_method = :mask
    security.mask_character = '*'  # Default
    
    # Example: "password123" becomes "***********"
    # Example: "john@example.com" becomes "***@example.com"
  end
end
```

### Removal

Completely remove sensitive fields:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    security.sanitization_method = :remove
    
    # Example: password field is completely removed from events
  end
end
```

### Hashing

Hash sensitive data for analytics while preserving uniqueness:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    security.sanitization_method = :hash
    security.hash_algorithm = :sha256  # :md5, :sha1, :sha256
    
    # Example: "password123" becomes "ef92b778bafe771e89245b89ecbc08a44a4e166c06659911881f383d4473e94f"
  end
end
```

### Custom Sanitization

Define custom sanitization logic:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    security.custom_sanitizer = ->(field_name, value) do
      case field_name
      when 'email'
        # Keep domain, mask local part
        local, domain = value.split('@')
        "#{local[0]}***@#{domain}"
      when 'phone'
        # Keep last 4 digits
        "***-***-#{value[-4..-1]}"
      when 'credit_card'
        # Keep last 4 digits
        "****-****-****-#{value[-4..-1]}"
      else
        # Default masking
        '*' * value.length
      end
    end
  end
end
```

## 📏 Payload & Field Limits

### Payload Size Limits

Prevent oversized payloads that could impact performance:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    # Maximum payload size (1MB)
    security.max_payload_size = 1024 * 1024
    
    # Maximum field value size (1KB)
    security.max_field_size = 1024
    
    # Maximum number of fields per event
    security.max_fields_per_event = 100
  end
end
```

### Field Value Truncation

Automatically truncate oversized values:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    # Truncate oversized values
    security.truncate_oversized_values = true
    
    # Truncation indicator
    security.truncation_indicator = '...'
    
    # Example: "very long text..." instead of rejecting the event
  end
end
```

## 🚫 Field Filtering

### Exclusion Lists

Always exclude sensitive fields:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    security.exclude_fields = [
      'password',
      'password_confirmation',
      'secret',
      'private_key',
      'session_data',
      'csrf_token',
      'authentication_token',
      'reset_token',
      'verification_code'
    ]
  end
end
```

### Inclusion Lists (Whitelist)

Only include specific fields:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    # When enabled, only these fields are included
    security.include_only_fields = [
      'id',
      'name',
      'email',
      'status',
      'created_at',
      'updated_at'
    ]
  end
end
```

### Nested Field Filtering

Filter nested object fields:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    security.exclude_nested_fields = [
      'user.password',
      'user.private_key',
      'order.payment.token',
      'config.secrets.api_key',
      'metadata.sensitive_data'
    ]
  end
end
```

## 🔐 Authentication & Encryption

### API Key Authentication

Secure delivery with API keys:

```ruby
EzlogsRubyAgent.configure do |c|
  c.delivery do |delivery|
    # API key from environment variable
    delivery.api_key = ENV['EZLOGS_API_KEY']
    
    # Custom headers for authentication
    delivery.custom_headers = {
      'Authorization' => "Bearer #{ENV['EZLOGS_API_KEY']}",
      'X-API-Key' => ENV['EZLOGS_API_KEY']
    }
  end
end
```

### TLS Encryption

Ensure secure transmission:

```ruby
EzlogsRubyAgent.configure do |c|
  c.delivery do |delivery|
    # Force HTTPS
    delivery.require_ssl = true
    
    # Custom SSL configuration
    delivery.ssl_verify_mode = OpenSSL::SSL::VERIFY_PEER
    delivery.ssl_ca_file = '/path/to/ca-certificates.crt'
  end
end
```

### Basic Authentication

Use username/password authentication:

```ruby
EzlogsRubyAgent.configure do |c|
  c.delivery do |delivery|
    delivery.username = ENV['EZLOGS_USERNAME']
    delivery.password = ENV['EZLOGS_PASSWORD']
  end
end
```

## 📋 Compliance Features

### GDPR Compliance

Configure for GDPR requirements:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    # Enable GDPR compliance features
    security.gdpr_compliance = true
    
    # Data retention settings
    security.data_retention_days = 90
    
    # Right to be forgotten
    security.enable_data_deletion = true
    
    # Data portability
    security.enable_data_export = true
  end
end
```

### CCPA Compliance

Configure for California Consumer Privacy Act:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    # Enable CCPA compliance features
    security.ccpa_compliance = true
    
    # Opt-out mechanisms
    security.enable_opt_out = true
    
    # Data disclosure requirements
    security.enable_data_disclosure = true
  end
end
```

### HIPAA Compliance

Configure for healthcare data:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    # Enable HIPAA compliance features
    security.hipaa_compliance = true
    
    # PHI detection and protection
    security.detect_phi = true
    
    # Audit logging
    security.enable_audit_logging = true
    
    # Access controls
    security.require_authentication = true
  end
end
```

## 🔍 Security Monitoring

### Security Event Logging

Track security-related events:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    # Log security events
    security.log_security_events = true
    
    # Security event types to log
    security.security_event_types = [
      'pii_detected',
      'field_sanitized',
      'payload_rejected',
      'authentication_failed',
      'access_denied'
    ]
  end
end
```

### Security Metrics

Monitor security metrics:

```ruby
# Get security metrics
security_metrics = EzlogsRubyAgent.security_monitor.metrics

puts "PII fields detected: #{security_metrics[:pii_fields_detected]}"
puts "Fields sanitized: #{security_metrics[:fields_sanitized]}"
puts "Payloads rejected: #{security_metrics[:payloads_rejected]}"
puts "Authentication failures: #{security_metrics[:auth_failures]}"
```

### Security Alerts

Set up security alerts:

```ruby
EzlogsRubyAgent.configure do |c|
  c.security do |security|
    # Alert on security events
    security.enable_security_alerts = true
    
    # Alert thresholds
    security.alert_thresholds = {
      pii_detected: 10,        # Alert if > 10 PII fields detected
      payload_rejected: 5,     # Alert if > 5 payloads rejected
      auth_failure: 3          # Alert if > 3 auth failures
    }
    
    # Alert handlers
    security.alert_handlers = [
      ->(event) { Rails.logger.warn("Security alert: #{event}") },
      ->(event) { SlackNotifier.notify_security(event) }
    ]
  end
end
```

## 🧪 Security Testing

### Security Test Helpers

Test security features in your test suite:

```ruby
# spec/support/ezlogs_security_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    # Enable security testing mode
    EzlogsRubyAgent.security_test_mode do
      # All security events are captured for testing
    end
  end
  
  config.after(:each) do
    EzlogsRubyAgent.clear_security_events
  end
end
```

### Security Test Examples

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

## 🚨 Security Best Practices

### Development

1. **Enable security features early** in development
2. **Test security configurations** thoroughly
3. **Use security test mode** in test suites
4. **Review security logs** regularly

### Production

1. **Always enable PII detection** in production
2. **Use environment variables** for sensitive configuration
3. **Monitor security metrics** continuously
4. **Set up security alerts** for critical events
5. **Regular security audits** of collected data

### Configuration

1. **Start with restrictive settings** and relax as needed
2. **Use whitelist approach** when possible
3. **Regularly review and update** security patterns
4. **Document security decisions** and rationale

### Data Handling

1. **Minimize data collection** - only collect what you need
2. **Sanitize data early** in the pipeline
3. **Use appropriate retention** periods
4. **Implement data deletion** capabilities

## 📚 Compliance Checklists

### GDPR Checklist

- [ ] Enable automatic PII detection
- [ ] Configure data retention periods
- [ ] Implement data deletion capabilities
- [ ] Provide data portability features
- [ ] Document data processing activities
- [ ] Establish data protection impact assessments

### CCPA Checklist

- [ ] Enable opt-out mechanisms
- [ ] Provide data disclosure capabilities
- [ ] Implement data deletion requests
- [ ] Maintain data processing records
- [ ] Train staff on privacy requirements

### HIPAA Checklist

- [ ] Enable PHI detection
- [ ] Implement access controls
- [ ] Enable audit logging
- [ ] Configure encryption in transit
- [ ] Establish breach notification procedures

## 📚 Next Steps

- **[Configuration Guide](configuration.md)** - Complete configuration options
- **[Performance Guide](performance.md)** - Optimization and tuning
- **[API Reference](../lib/ezlogs_ruby_agent.rb)** - Complete API documentation
- **[Examples](../examples/)** - Complete example applications

---

**Security is not optional - it's built into every aspect of EZLogs.** Use these guidelines to ensure your event tracking system protects sensitive data and maintains compliance! 🛡️ 