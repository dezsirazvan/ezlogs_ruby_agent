require 'spec_helper'

RSpec.describe EzlogsRubyAgent::EventPool do
  let(:event) do
    EzlogsRubyAgent::UniversalEvent.new(event_type: 'test.event', action: 'test', actor: { type: 'system', id: '1' })
  end

  it 'gets a new event from the pool' do
    e = described_class.get_event
    expect(e).to be_a(EzlogsRubyAgent::UniversalEvent)
  end

  it 'returns an event to the pool' do
    expect { described_class.return_event(event) }.not_to raise_error
  end

  it 'updates pool stats' do
    before_stats = described_class.pool_stats[:pool_size]
    described_class.return_event(event)
    after_stats = described_class.pool_stats[:pool_size]
    expect(after_stats).to be >= before_stats
  end

  it 'clears the pool' do
    described_class.return_event(event)
    described_class.clear_pool
    expect(described_class.pool_stats[:pool_size]).to eq(0)
  end

  it 'reuses events if possible' do
    described_class.clear_pool
    described_class.return_event(event)
    e2 = described_class.get_event
    expect(e2).to be_a(EzlogsRubyAgent::UniversalEvent)
  end
end
