require 'spec_helper'
require 'ezlogs_ruby_agent'

RSpec.describe 'Security Production Validation', type: :validation do
  let(:processor) { EzlogsRubyAgent::EventProcessor.new(auto_detect_pii: true) }
  let(:config) { EzlogsRubyAgent::Configuration.new }

  before do
    config.service_name = 'security-test'
    config.environment = 'test'
  end

  describe 'PII Detection and Redaction' do
    it 'detects and redacts all PII patterns accurately' do
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'user.action',
        action: 'profile.updated',
        actor: { type: 'user', id: '123' },
        metadata: {
          credit_card: '4111-1111-1111-1111',
          ssn: '123-45-6789',
          phone: '(555) 123-4567',
          email: 'user@example.com',
          safe_field: 'totally safe data',
          description: 'User updated their email from old@example.com to new@example.com'
        }
      )

      result = processor.process(event)

      expect(result[:metadata][:credit_card]).to eq('[REDACTED]')
      expect(result[:metadata][:ssn]).to eq('[REDACTED]')
      expect(result[:metadata][:phone]).to eq('[REDACTED]')
      expect(result[:metadata][:email]).to eq('[REDACTED]')
      expect(result[:metadata][:safe_field]).to eq('totally safe data')
      expect(result[:metadata][:description]).to include('[REDACTED]') # Email in text
    end

    it 'handles various credit card formats' do
      credit_cards = [
        '4111-1111-1111-1111',
        '4111 1111 1111 1111',
        '4111111111111111',
        '5555-4444-3333-2222',
        '3782-822463-10005', # American Express
        '6011-1111-1111-1117' # Discover
      ]

      credit_cards.each do |card|
        event = EzlogsRubyAgent::UniversalEvent.new(
          event_type: 'payment.processed',
          action: 'card.charged',
          actor: { type: 'user', id: '123' },
          metadata: { card_number: card }
        )

        result = processor.process(event)
        expect(result[:metadata][:card_number]).to eq('[REDACTED]')
      end
    end

    it 'handles various SSN formats' do
      ssns = [
        '123-45-6789',
        '123456789',
        '123 45 6789'
      ]

      ssns.each do |ssn|
        event = EzlogsRubyAgent::UniversalEvent.new(
          event_type: 'user.action',
          action: 'ssn.updated',
          actor: { type: 'user', id: '123' },
          metadata: { social_security: ssn }
        )

        result = processor.process(event)
        expect(result[:metadata][:social_security]).to eq('[REDACTED]')
      end
    end

    it 'handles various phone number formats' do
      phones = [
        '(555) 123-4567',
        '555-123-4567',
        '555.123.4567',
        '5551234567',
        '+1-555-123-4567'
      ]

      phones.each do |phone|
        event = EzlogsRubyAgent::UniversalEvent.new(
          event_type: 'user.action',
          action: 'phone.updated',
          actor: { type: 'user', id: '123' },
          metadata: { phone_number: phone }
        )

        result = processor.process(event)
        expect(result[:metadata][:phone_number]).to eq('[REDACTED]')
      end
    end

    it 'handles email addresses in various contexts' do
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'user.action',
        action: 'profile.updated',
        actor: { type: 'user', id: '123' },
        metadata: {
          primary_email: 'user@example.com',
          backup_email: 'backup@example.org',
          description: 'Contact user@example.com for support',
          safe_text: 'This is safe text without emails'
        }
      )

      result = processor.process(event)

      expect(result[:metadata][:primary_email]).to eq('[REDACTED]')
      expect(result[:metadata][:backup_email]).to eq('[REDACTED]')
      expect(result[:metadata][:description]).to include('[REDACTED]')
      expect(result[:metadata][:safe_text]).to eq('This is safe text without emails')
    end
  end

  describe 'Field-Based Sanitization' do
    it 'sanitizes sensitive field names regardless of case' do
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'user.action',
        action: 'credentials.updated',
        actor: { type: 'user', id: '123' },
        metadata: {
          PASSWORD: 'secret123',
          PassWord: 'secret456',
          password: 'secret789',
          API_KEY: 'key123',
          access_token: 'token456',
          session_id: 'sess789',
          credit_card_number: '4111-1111-1111-1111'
        }
      )

      result = processor.process(event)

      expect(result[:metadata][:PASSWORD]).to eq('[REDACTED]')
      expect(result[:metadata][:PassWord]).to eq('[REDACTED]')
      expect(result[:metadata][:password]).to eq('[REDACTED]')
      expect(result[:metadata][:API_KEY]).to eq('[REDACTED]')
      expect(result[:metadata][:access_token]).to eq('[REDACTED]')
      expect(result[:metadata][:session_id]).to eq('[REDACTED]')
      expect(result[:metadata][:credit_card_number]).to eq('[REDACTED]')
    end

    it 'sanitizes nested sensitive fields' do
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'user.action',
        action: 'profile.updated',
        actor: { type: 'user', id: '123' },
        metadata: {
          user_data: {
            name: 'John Doe',
            password: 'secret123',
            credentials: {
              api_key: 'key123',
              access_token: 'token456'
            }
          },
          safe_data: {
            preferences: {
              theme: 'dark',
              language: 'en'
            }
          }
        }
      )

      result = processor.process(event)

      expect(result[:metadata][:user_data][:name]).to eq('John Doe')
      expect(result[:metadata][:user_data][:password]).to eq('[REDACTED]')
      expect(result[:metadata][:user_data][:credentials][:api_key]).to eq('[REDACTED]')
      expect(result[:metadata][:user_data][:credentials][:access_token]).to eq('[REDACTED]')
      expect(result[:metadata][:safe_data][:preferences][:theme]).to eq('dark')
    end

    it 'sanitizes sensitive fields in arrays' do
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'user.action',
        action: 'accounts.updated',
        actor: { type: 'user', id: '123' },
        metadata: {
          accounts: [
            { name: 'Account 1', password: 'pass1' },
            { name: 'Account 2', api_key: 'key2' },
            { name: 'Account 3', token: 'token3' }
          ]
        }
      )

      result = processor.process(event)

      expect(result[:metadata][:accounts][0][:name]).to eq('Account 1')
      expect(result[:metadata][:accounts][0][:password]).to eq('[REDACTED]')
      expect(result[:metadata][:accounts][1][:name]).to eq('Account 2')
      expect(result[:metadata][:accounts][1][:api_key]).to eq('[REDACTED]')
      expect(result[:metadata][:accounts][2][:name]).to eq('Account 3')
      expect(result[:metadata][:accounts][2][:token]).to eq('[REDACTED]')
    end
  end

  describe 'Custom PII Patterns' do
    it 'supports custom PII detection patterns' do
      custom_processor = EzlogsRubyAgent::EventProcessor.new(
        auto_detect_pii: true,
        custom_patterns: {
          'custom_id' => /\bCUST-\d{6}\b/,
          'internal_code' => /\bINT-\w{8}\b/
        }
      )

      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'user.action',
        action: 'data.updated',
        actor: { type: 'user', id: '123' },
        metadata: {
          customer_id: 'CUST-123456',
          internal_code: 'INT-ABCD1234',
          safe_field: 'CUST-ABC' # Doesn't match pattern
        }
      )

      result = custom_processor.process(event)

      expect(result[:metadata][:customer_id]).to eq('[REDACTED]')
      expect(result[:metadata][:internal_code]).to eq('[REDACTED]')
      expect(result[:metadata][:safe_field]).to eq('CUST-ABC')
    end

    it 'allows disabling automatic PII detection but still redacts by field name' do
      disabled_processor = EzlogsRubyAgent::EventProcessor.new(auto_detect_pii: false)

      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'user.action',
        action: 'profile.updated',
        actor: { type: 'user', id: '123' },
        metadata: {
          email: 'user@example.com', # Should NOT be redacted by field name
          credit_card: '4111-1111-1111-1111', # Should be redacted by field name
          password: 'secret123', # Should ALWAYS be redacted by field name
          safe_field: 'public data'
        }
      )

      result = disabled_processor.process(event)

      # Field-based redaction always applies
      expect(result[:metadata][:password]).to eq('[REDACTED]')
      expect(result[:metadata][:credit_card]).to eq('[REDACTED]')
      # Pattern-based redaction does NOT apply
      expect(result[:metadata][:email]).to eq('user@example.com')
      expect(result[:metadata][:safe_field]).to eq('public data')
    end
  end

  describe 'Payload Size Limits' do
    it 'enforces payload size limits strictly' do
      large_data = 'x' * (1024 * 1024) # 1MB
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.large',
        action: 'create',
        actor: { type: 'system', id: '1' },
        metadata: { large_field: large_data }
      )

      processor = EzlogsRubyAgent::EventProcessor.new(max_payload_size: 64 * 1024) # 64KB limit

      expect do
        processor.process(event)
      end.to raise_error(EzlogsRubyAgent::PayloadTooLargeError, /exceeds maximum size/)
    end

    it 'allows events within size limits' do
      reasonable_data = 'x' * 1000 # 1KB
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.reasonable',
        action: 'create',
        actor: { type: 'system', id: '1' },
        metadata: { reasonable_field: reasonable_data }
      )

      processor = EzlogsRubyAgent::EventProcessor.new(max_payload_size: 64 * 1024) # 64KB limit

      expect do
        processor.process(event)
      end.not_to raise_error
    end

    it 'provides helpful error messages for size violations' do
      large_data = 'x' * (100 * 1024) # 100KB
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.large',
        action: 'create',
        actor: { type: 'system', id: '1' },
        metadata: { large_field: large_data }
      )

      processor = EzlogsRubyAgent::EventProcessor.new(max_payload_size: 50 * 1024) # 50KB limit

      begin
        processor.process(event)
      rescue EzlogsRubyAgent::PayloadTooLargeError => e
        expect(e.message).to include('exceeds maximum size')
        expect(e.message).to include('bytes')
      end
    end
  end

  describe 'Sampling Security' do
    it 'maintains security with sampling enabled' do
      processor = EzlogsRubyAgent::EventProcessor.new(sample_rate: 0.5)

      events = []
      100.times do |i|
        event = EzlogsRubyAgent::UniversalEvent.new(
          event_type: 'test.sampling',
          action: 'test',
          actor: { type: 'user', id: i.to_s },
          metadata: {
            password: 'secret123',
            email: 'user@example.com'
          }
        )
        result = processor.process(event)
        events << result if result
      end

      # Some events should be sampled out
      expect(events.length).to be < 100

      # All processed events should have security applied
      events.each do |event|
        expect(event[:metadata][:password]).to eq('[REDACTED]')
        expect(event[:metadata][:email]).to eq('[REDACTED]')
      end
    end

    it 'uses deterministic sampling for consistent results' do
      processor = EzlogsRubyAgent::EventProcessor.new(
        sample_rate: 0.5,
        deterministic_sampling: true
      )

      event1 = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.deterministic',
        action: 'test1',
        actor: { type: 'user', id: '123' }
      )

      event2 = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.deterministic',
        action: 'test2',
        actor: { type: 'user', id: '123' }
      )

      # Same event ID should always have same sampling result
      result1 = processor.process(event1)
      result2 = processor.process(event1)

      expect(result1.nil?).to eq(result2.nil?)
    end
  end

  describe 'Error Handling Security' do
    it 'does not leak sensitive data in error messages' do
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.error',
        action: 'test',
        actor: { type: 'user', id: '123' },
        metadata: {
          password: 'secret123',
          api_key: 'key456',
          error_details: 'Contains sensitive info: user@example.com'
        }
      )

      # Mock JSON generation to fail
      allow(JSON).to receive(:generate).and_raise(StandardError, 'JSON error')

      begin
        processor.process(event)
      rescue StandardError => e
        # Error message should not contain sensitive data
        expect(e.message).not_to include('secret123')
        expect(e.message).not_to include('key456')
        expect(e.message).not_to include('user@example.com')
      end
    end
  end

  describe 'Processing Metadata Security' do
    it 'includes security processing information' do
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.security',
        action: 'test',
        actor: { type: 'user', id: '123' },
        metadata: {
          password: 'secret123',
          email: 'user@example.com',
          safe_field: 'public data'
        }
      )

      result = processor.process(event)

      expect(result[:processing]).to be_present
      expect(result[:processing][:security_applied]).to be true
      # The actual sanitized_fields are full paths like 'metadata.password', 'metadata.email'
      expect(result[:processing][:sanitized_fields]).to include('metadata.password')
      expect(result[:processing][:sanitized_fields]).to include('metadata.email')
      expect(result[:processing][:sanitized_fields]).not_to include('metadata.safe_field')
    end

    it 'tracks processing version for security updates' do
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.version',
        action: 'test',
        actor: { type: 'user', id: '123' }
      )

      result = processor.process(event)

      expect(result[:processing][:processor_version]).to eq(EzlogsRubyAgent::EventProcessor::VERSION)
    end
  end
end
