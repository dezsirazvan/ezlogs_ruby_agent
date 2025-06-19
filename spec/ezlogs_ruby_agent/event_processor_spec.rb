require 'spec_helper'

RSpec.describe EzlogsRubyAgent::EventProcessor do
  let(:processor) { described_class.new }
  let(:valid_event) do
    EzlogsRubyAgent::UniversalEvent.new(
      event_type: 'user.action',
      action: 'profile.updated',
      actor: { type: 'user', id: '123', email: 'user@example.com' },
      subject: { type: 'profile', id: '456' },
      metadata: {
        field: 'email',
        old_value: 'old@example.com',
        new_value: 'new@example.com',
        credit_card: '4111111111111111',
        ssn: '123-45-6789'
      }
    )
  end

  describe '#process' do
    it 'processes valid events and returns processed event' do
      result = processor.process(valid_event)

      expect(result).to be_a(Hash)
      expect(result[:event_id]).to eq(valid_event.event_id)
      expect(result[:event_type]).to eq('user.action')
    end

    it 'applies security sanitization by default' do
      result = processor.process(valid_event)

      # Should sanitize sensitive fields
      expect(result[:metadata][:credit_card]).to eq('[REDACTED]')
      expect(result[:metadata][:ssn]).to eq('[REDACTED]')

      # Should sanitize email addresses detected by PII patterns
      expect(result[:actor][:email]).to eq('[REDACTED]')

      # Should keep safe fields
      expect(result[:metadata][:field]).to eq('email')
    end

    it 'respects sampling configuration' do
      # Configure for 0% sampling (no events should pass)
      processor = described_class.new(sample_rate: 0.0)
      result = processor.process(valid_event)

      expect(result).to be_nil
    end

    it 'always processes events when sampling is 1.0' do
      processor = described_class.new(sample_rate: 1.0)
      result = processor.process(valid_event)

      expect(result).not_to be_nil
      expect(result[:event_id]).to eq(valid_event.event_id)
    end

    it 'validates payload size limits' do
      large_metadata = { data: 'x' * 1_000_000 } # 1MB of data
      large_event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.large',
        action: 'create',
        actor: { type: 'system', id: '1' },
        metadata: large_metadata
      )

      processor = described_class.new(max_payload_size: 1024) # 1KB limit

      expect do
        processor.process(large_event)
      end.to raise_error(EzlogsRubyAgent::PayloadTooLargeError, /exceeds maximum size/)
    end

    it 'adds processing timestamp and metadata' do
      freeze_time = Time.parse('2025-01-21T15:30:00Z')
      Timecop.freeze(freeze_time) do
        result = processor.process(valid_event)

        expect(result[:processing]).to include(
          processed_at: freeze_time,
          processor_version: be_a(String),
          sanitized_fields: be_an(Array)
        )
      end
    end
  end

  describe '#sample?' do
    it 'returns true for sample_rate of 1.0' do
      processor = described_class.new(sample_rate: 1.0)
      expect(processor.send(:sample?)).to be true
    end

    it 'returns false for sample_rate of 0.0' do
      processor = described_class.new(sample_rate: 0.0)
      expect(processor.send(:sample?)).to be false
    end

    it 'uses deterministic sampling based on event ID when enabled' do
      processor = described_class.new(sample_rate: 0.5, deterministic_sampling: true)
      event_id = 'evt_test123'

      # Same event ID should always return same result
      result1 = processor.send(:sample?, event_id)
      result2 = processor.send(:sample?, event_id)

      expect(result1).to eq(result2)
    end
  end

  describe 'security sanitization' do
    let(:processor) { described_class.new(auto_detect_pii: true) }

    it 'detects and redacts credit card numbers' do
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'payment.processed',
        action: 'charge',
        actor: { type: 'user', id: '123' },
        metadata: {
          card_number: '4111-1111-1111-1111',
          amount: 100.00,
          description: 'Payment for order #123'
        }
      )

      result = processor.process(event)

      expect(result[:metadata][:card_number]).to eq('[REDACTED]')
      expect(result[:metadata][:amount]).to eq(100.00)
      expect(result[:processing][:sanitized_fields]).to include('metadata.card_number')
    end

    it 'detects and redacts email addresses when configured' do
      processor = described_class.new(
        sanitize_fields: ['email'],
        auto_detect_pii: false
      )

      result = processor.process(valid_event)

      expect(result[:actor][:email]).to eq('[REDACTED]')
      expect(result[:processing][:sanitized_fields]).to include('actor.email')
    end

    it 'supports custom sanitization patterns' do
      processor = described_class.new(
        custom_patterns: {
          'api_key' => /^sk_[a-zA-Z0-9]{24}$/,
          'token' => /^[a-zA-Z0-9]{32}$/
        }
      )

      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'api.request',
        action: 'authenticate',
        actor: { type: 'service', id: 'api' },
        metadata: {
          api_key: 'sk_1234567890abcdef12345678',
          token: 'abcdef1234567890abcdef1234567890',
          user_id: '12345'
        }
      )

      result = processor.process(event)

      expect(result[:metadata][:api_key]).to eq('[REDACTED]')
      expect(result[:metadata][:token]).to eq('[REDACTED]')
      expect(result[:metadata][:user_id]).to eq('12345')
    end
  end

  describe 'configuration' do
    it 'accepts configuration options' do
      processor = described_class.new(
        sample_rate: 0.5,
        max_payload_size: 2048,
        auto_detect_pii: false,
        sanitize_fields: %w[password token]
      )

      expect(processor.instance_variable_get(:@sample_rate)).to eq(0.5)
      expect(processor.instance_variable_get(:@max_payload_size)).to eq(2048)
      expect(processor.instance_variable_get(:@auto_detect_pii)).to be false
      expect(processor.instance_variable_get(:@sanitize_fields)).to eq(%w[password token])
    end

    it 'uses sensible defaults' do
      processor = described_class.new

      expect(processor.instance_variable_get(:@sample_rate)).to eq(1.0)
      expect(processor.instance_variable_get(:@max_payload_size)).to eq(64 * 1024)
      expect(processor.instance_variable_get(:@auto_detect_pii)).to be true
    end
  end
end
