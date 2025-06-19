require 'spec_helper'

RSpec.describe EzlogsRubyAgent::EventWriter do
  let(:writer) { described_class.new }
  let(:event) do
    EzlogsRubyAgent::UniversalEvent.new(event_type: 'test.event', action: 'test', actor: { type: 'system', id: '1' })
  end

  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
    end
    allow(writer).to receive(:send_batch).and_return(true)
  end

  after do
    writer.shutdown
  end

  it 'enqueues UniversalEvent for processing' do
    expect { writer.log(event) }.not_to raise_error
  end

  it 'enqueues legacy hash as UniversalEvent' do
    legacy = { 'event_type' => 'legacy.event', 'action' => 'legacy', 'actor' => { 'type' => 'system', 'id' => '1' } }
    expect { writer.log(legacy) }.not_to raise_error
  end

  it 'processes batch and updates metrics' do
    3.times { writer.log(event) }
    # Give the background thread time to process
    sleep(0.1)
    expect(writer.metrics[:events_received]).to be >= 3
  end

  it 'returns health status' do
    status = writer.health_status
    expect(status).to include(:queue_size, :max_buffer, :metrics, :thread_alive)
  end

  it 'handles buffer overflow gracefully' do
    allow(writer.instance_variable_get(:@queue)).to receive(:<<).and_raise(ThreadError)
    expect { writer.log(event) }.not_to raise_error
  end

  it 'flushes on exit' do
    expect { writer.send(:flush_on_exit) }.not_to raise_error
  end

  it 'handles nil events gracefully' do
    expect { writer.log(nil) }.not_to raise_error
  end

  it 'handles invalid events gracefully' do
    expect { writer.log('invalid') }.not_to raise_error
  end
end
