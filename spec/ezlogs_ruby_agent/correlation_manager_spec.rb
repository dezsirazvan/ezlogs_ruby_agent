require 'spec_helper'

RSpec.describe EzlogsRubyAgent::CorrelationManager do
  describe '.start_request_context' do
    it 'creates a new request context with correlation ID' do
      context = described_class.start_request_context('req_123', 'sess_456')

      expect(context).to be_a(described_class::Context)
      expect(context.request_id).to eq('req_123')
      expect(context.session_id).to eq('sess_456')
      expect(context.correlation_id).to match(/^corr_/)
      expect(context.flow_id).to match(/^flow_/)
    end

    it 'sets the context as current' do
      context = described_class.start_request_context('req_123')
      current = described_class.current_context

      expect(current).to eq(context)
    end

    it 'includes metadata in context' do
      metadata = { user_id: '123', action: 'login' }
      context = described_class.start_request_context('req_123', nil, metadata)

      expect(context.metadata).to include(metadata)
    end
  end

  describe '.start_flow_context' do
    it 'creates a new flow context with flow ID' do
      context = described_class.start_flow_context('user_registration', 'user_123')
      expect(context.flow_id).to eq('flow_user_registration_user_123')
      expect(context.correlation_id).to match(/^corr_/) # still random
    end
  end

  describe '.inherit_context' do
    let(:parent_context) do
      described_class::Context.new(
        correlation_id: 'corr_parent',
        flow_id: 'flow_parent',
        session_id: 'sess_parent',
        request_id: 'req_parent'
      )
    end

    it 'inherits correlation data from parent context' do
      inherited = described_class.inherit_context(parent_context)

      expect(inherited.correlation_id).to eq('corr_parent')
      expect(inherited.flow_id).to eq('flow_parent')
      expect(inherited.session_id).to eq('sess_parent')
      expect(inherited.request_id).to eq('req_parent')
    end

    it 'adds inheritance metadata' do
      inherited = described_class.inherit_context(parent_context)

      expect(inherited.metadata[:inherited_from]).to eq('corr_parent')
      expect(inherited.metadata[:inherited_at]).to be_present
    end

    it 'handles nil parent context gracefully' do
      inherited = described_class.inherit_context(nil)
      expect(inherited.flow_id).to match(/^flow_async_/)
      expect(inherited.correlation_id).to match(/^corr_/) # still random
    end

    it 'merges with existing context' do
      parent = described_class.start_request_context('req_parent', nil, { correlation_id: 'corr_parent' })
      inherited = described_class.inherit_context(parent)
      expect(inherited.correlation_id).to eq('corr_parent')
    end
  end

  describe '.current_context' do
    it 'returns nil when no context is set' do
      described_class.clear_context
      expect(described_class.current_context).to be_nil
    end

    it 'returns the current context' do
      context = described_class.start_request_context('req_123')
      expect(described_class.current_context).to eq(context)
    end
  end

  describe '.with_context' do
    it 'executes block with specific context' do
      context = described_class::Context.new(correlation_id: 'test_corr')
      result = nil

      described_class.with_context(context) do
        result = described_class.current_context
      end

      expect(result).to eq(context)
    end

    it 'restores previous context after execution' do
      original = described_class.start_request_context('req_original')
      context = described_class::Context.new(correlation_id: 'test_corr')

      described_class.with_context(context) do
        expect(described_class.current_context).to eq(context)
      end

      expect(described_class.current_context).to eq(original)
    end

    it 'restores context even if block raises error' do
      original = described_class.start_request_context('req_original')
      context = described_class::Context.new(correlation_id: 'test_corr')

      expect do
        described_class.with_context(context) do
          raise 'test error'
        end
      end.to raise_error('test error')

      expect(described_class.current_context).to eq(original)
    end
  end

  describe '.clear_context' do
    it 'clears the current context' do
      described_class.start_request_context('req_123')
      expect(described_class.current_context).to be_present

      described_class.clear_context
      expect(described_class.current_context).to be_nil
    end
  end

  describe '.create_child_context' do
    it 'creates child context with parent event ID' do
      parent = described_class.start_request_context('req_123')
      child = described_class.create_child_context('evt_child')

      expect(child.correlation_id).to eq(parent.correlation_id)
      expect(child.flow_id).to eq(parent.flow_id)
      expect(child.parent_event_id).to eq('evt_child')
    end

    it 'handles no current context gracefully' do
      child = described_class.create_child_context('evt_123')
      expect(child.flow_id).to match(/^flow_orphaned_/)
      expect(child.correlation_id).to match(/^corr_/) # still random
    end
  end

  describe '.extract_correlation_data' do
    it 'extracts serializable correlation data' do
      context = described_class.start_request_context('req_123', 'sess_456')
      data = described_class.extract_correlation_data

      expect(data).to be_a(Hash)
      expect(data[:correlation_id]).to eq(context.correlation_id)
      expect(data[:flow_id]).to eq(context.flow_id)
      expect(data[:session_id]).to eq('sess_456')
      expect(data[:request_id]).to eq('req_123')
    end

    it 'returns empty hash when no context' do
      described_class.clear_context
      data = described_class.extract_correlation_data

      expect(data).to eq({})
    end
  end

  describe '.restore_context' do
    it 'restores context from serialized data' do
      original = described_class.start_request_context('req_1', 'session_1', { user_id: 42 })
      data = original.to_h
      restored = described_class.restore_context(data)
      expect(restored.request_id).to eq('req_1')
      expect(restored.session_id).to eq('session_1')
      expect(restored.metadata[:user_id]).to eq(42)
    end

    it 'handles invalid data gracefully' do
      restored = described_class.restore_context(nil)
      expect(restored).to be_nil

      restored = described_class.restore_context('invalid')
      expect(restored).to be_nil
    end
  end

  describe 'thread safety' do
    it 'maintains separate contexts across threads' do
      context1 = described_class.start_request_context('req_1')

      thread_context = nil
      thread = Thread.new do
        context2 = described_class.start_request_context('req_2')
        thread_context = described_class.current_context
        context2
      end

      thread_result = thread.value

      expect(thread_context).to eq(thread_result)
      expect(described_class.current_context).to eq(context1)
      expect(thread_context).not_to eq(context1)
    end
  end

  describe 'Context class' do
    describe '#to_h' do
      it 'converts context to hash' do
        context = described_class::Context.new(
          correlation_id: 'corr_123',
          flow_id: 'flow_123',
          session_id: 'sess_123',
          request_id: 'req_123',
          parent_event_id: 'evt_123'
        )

        hash = context.to_h

        expect(hash).to eq({
          correlation_id: 'corr_123',
          flow_id: 'flow_123',
          session_id: 'sess_123',
          request_id: 'req_123',
          parent_event_id: 'evt_123',
          started_at: context.started_at,
          metadata: {}
        })
      end

      it 'omits nil values' do
        context = described_class::Context.new(correlation_id: 'corr_123')
        hash = context.to_h

        expect(hash).not_to have_key(:session_id)
        expect(hash).not_to have_key(:request_id)
        expect(hash).not_to have_key(:parent_event_id)
      end
    end

    describe '#merge' do
      it 'merges with another context' do
        context1 = described_class::Context.new(
          correlation_id: 'corr_1',
          session_id: 'sess_1'
        )

        context2 = described_class::Context.new(
          correlation_id: 'corr_2',
          request_id: 'req_2'
        )

        merged = context1.merge(context2)

        expect(merged.correlation_id).to eq('corr_1')
        expect(merged.session_id).to eq('sess_1')
        expect(merged.request_id).to eq('req_2')
      end

      it 'returns self when other context is nil' do
        context = described_class::Context.new(correlation_id: 'corr_123')
        merged = context.merge(nil)

        expect(merged).to eq(context)
      end
    end
  end

  let(:manager) { described_class }

  it 'provides a thread-safe context API' do
    main_context = manager.current_context
    t = Thread.new do
      manager.with_context(request_id: 't1') do
        expect(manager.current_context.request_id).to eq('t1')
      end
    end
    t.join
    expect(manager.current_context).to eq(main_context)
  end

  it 'propagates context within block' do
    manager.with_context(request_id: 'req1', session_id: 'sess1') do
      expect(manager.current_context.request_id).to eq('req1')
      expect(manager.current_context.session_id).to eq('sess1')
    end
  end

  it 'restores previous context after block' do
    # Create an initial context first
    manager.start_request_context('req_original')
    orig = manager.current_context
    manager.with_context(request_id: 'temp') {}
    expect(manager.current_context.request_id).to eq(orig.request_id)
  end

  it 'handles nested context blocks' do
    manager.with_context(request_id: 'req1') do
      manager.with_context(session_id: 'sess1') do
        expect(manager.current_context.request_id).to eq('req1')
        expect(manager.current_context.session_id).to eq('sess1')
      end
    end
  end

  it 'handles nil context gracefully' do
    expect { manager.with_context(nil) {} }.not_to raise_error
  end
end
