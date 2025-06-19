require 'spec_helper'

RSpec.describe EzlogsRubyAgent::UniversalEvent do
  describe '.new' do
    let(:valid_attributes) do
      {
        event_type: 'user.action',
        action: 'profile.updated',
        actor: { type: 'user', id: '123' },
        subject: { type: 'profile', id: '456' },
        metadata: { field: 'email', old_value: 'old@example.com', new_value: 'new@example.com' }
      }
    end

    it 'creates an event with valid attributes' do
      event = described_class.new(**valid_attributes)

      expect(event.event_type).to eq('user.action')
      expect(event.action).to eq('profile.updated')
      expect(event.actor).to eq({ type: 'user', id: '123' })
      expect(event.subject).to eq({ type: 'profile', id: '456' })
    end

    it 'generates a unique event_id automatically' do
      event1 = described_class.new(**valid_attributes)
      event2 = described_class.new(**valid_attributes)

      expect(event1.event_id).to be_a(String)
      expect(event1.event_id).not_to eq(event2.event_id)
      expect(event1.event_id).to match(/^evt_[a-zA-Z0-9]{22}$/)
    end

    it 'sets timestamp automatically if not provided' do
      freeze_time = Time.parse('2025-01-21T10:30:00Z')
      Timecop.freeze(freeze_time) do
        event = described_class.new(**valid_attributes)
        expect(event.timestamp).to eq(freeze_time)
      end
    end

    it 'uses provided timestamp when given' do
      custom_time = Time.parse('2025-01-20T15:45:00Z')
      event = described_class.new(**valid_attributes.merge(timestamp: custom_time))

      expect(event.timestamp).to eq(custom_time)
    end

    it 'generates correlation_id from thread context' do
      Thread.current[:ezlogs_context] = { correlation_id: 'req_123abc' }
      event = described_class.new(**valid_attributes)

      expect(event.correlation_id).to eq('req_123abc')
    ensure
      Thread.current[:ezlogs_context] = nil
    end

    it 'generates unique correlation_id when not in context' do
      event = described_class.new(**valid_attributes)

      expect(event.correlation_id).to be_a(String)
      expect(event.correlation_id).to match(/^flow_[a-zA-Z0-9]{22}$/)
    end

    it 'raises error for missing required fields' do
      expect { described_class.new }.to raise_error(ArgumentError, /missing keyword/)
      expect { described_class.new(event_type: 'test') }.to raise_error(ArgumentError, /missing keyword/)
    end

    it 'validates event_type format' do
      expect do
        described_class.new(**valid_attributes.merge(event_type: 'invalid-type'))
      end.to raise_error(EzlogsRubyAgent::InvalidEventError, /event_type must match pattern/)
    end

    it 'validates actor structure' do
      expect do
        described_class.new(**valid_attributes.merge(actor: { id: '123' }))
      end.to raise_error(EzlogsRubyAgent::InvalidEventError, /actor must have type/)

      expect do
        described_class.new(**valid_attributes.merge(actor: { type: 'user' }))
      end.to raise_error(EzlogsRubyAgent::InvalidEventError, /actor must have id/)
    end
  end

  describe '#to_h' do
    let(:event) do
      described_class.new(
        event_type: 'http.request',
        action: 'GET',
        actor: { type: 'user', id: '123', email: 'user@example.com' },
        subject: { type: 'endpoint', id: '/api/users' },
        metadata: { status: 200, duration: 0.150 }
      )
    end

    it 'returns complete event as hash' do
      hash = event.to_h

      expect(hash).to include(
        event_id: event.event_id,
        timestamp: event.timestamp,
        event_type: 'http.request',
        action: 'GET',
        actor: { type: 'user', id: '123', email: 'user@example.com' },
        subject: { type: 'endpoint', id: '/api/users' },
        correlation: hash_including(correlation_id: event.correlation_id),
        metadata: { status: 200, duration: 0.150 },
        platform: hash_including(
          service: be_a(String),
          environment: be_a(String),
          agent_version: EzlogsRubyAgent::VERSION
        )
      )
    end

    it 'includes platform information automatically' do
      hash = event.to_h

      expect(hash[:platform]).to include(
        service: be_a(String),
        environment: be_a(String),
        agent_version: EzlogsRubyAgent::VERSION,
        ruby_version: RUBY_VERSION
      )
    end
  end

  describe '#immutable' do
    let(:event) { described_class.new(event_type: 'test.action', action: 'test', actor: { type: 'system', id: '1' }) }

    it 'prevents modification of event attributes' do
      expect { event.event_id = 'new_id' }.to raise_error(NoMethodError)
      expect { event.timestamp = Time.now }.to raise_error(NoMethodError)
      expect { event.actor[:id] = 'new_id' }.to raise_error(FrozenError)
    end

    it 'returns frozen objects' do
      expect(event.actor).to be_frozen
      expect(event.correlation).to be_frozen
      expect(event.platform).to be_frozen
    end
  end

  describe '#valid?' do
    it 'returns true for valid events' do
      event = described_class.new(
        event_type: 'user.action',
        action: 'login',
        actor: { type: 'user', id: '123' }
      )

      expect(event).to be_valid
    end

    it 'provides validation errors for invalid events' do
      # This will test validation on invalid events that don't raise during construction
      expect do
        described_class.new(
          event_type: 'invalid-type',
          action: 'test',
          actor: { id: '123' }
        )
      end.to raise_error(EzlogsRubyAgent::InvalidEventError) do |error|
        expect(error.message).to include('event_type must match pattern')
        expect(error.message).to include('actor must have type')
      end
    end
  end
end
