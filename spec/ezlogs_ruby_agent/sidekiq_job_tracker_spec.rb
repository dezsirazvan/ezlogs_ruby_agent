require 'spec_helper'

RSpec.describe EzlogsRubyAgent::SidekiqJobTracker do
  let(:tracker) { described_class.new }
  let(:worker) { double('Worker', class: double(name: 'TestWorker')) }
  let(:queue) { 'default' }
  let(:job_class) { Class.new { def self.name = 'TestJob' } }
  let(:job_args) { [1, 2, 3] }
  let(:job_hash) { { 'class' => job_class, 'args' => job_args, 'jid' => 'abc123', 'queue' => 'default' } }
  let(:context) { { request_id: 'req-1', correlation_id: 'corr-1' } }

  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
      config.included_resources = []
      config.excluded_resources = []
    end
    allow(EzlogsRubyAgent.writer).to receive(:log)
    allow(EzlogsRubyAgent::CorrelationManager).to receive(:current_context).and_return(context)
    allow(EzlogsRubyAgent::EventWriter).to receive(:log)
  end

  it 'restores correlation from job hash' do
    job = { '_correlation_data' => { correlation_id: 'corr_abc' }, 'args' => [{}], 'jid' => 'jid1',
            'queue' => 'default' }
    expect(EzlogsRubyAgent::CorrelationManager).to receive(:inherit_context).with(job['_correlation_data'])
    begin
      tracker.call(worker, job, queue) { 'ok' }
    rescue StandardError
      nil
    end
  end

  it 'logs UniversalEvent with correct schema on success' do
    job = { 'args' => [{ id: 42 }], 'jid' => 'jid2', 'queue' => 'default' }
    expect(EzlogsRubyAgent.writer).to receive(:log).with(instance_of(EzlogsRubyAgent::UniversalEvent))
    tracker.call(worker, job, queue) { 'ok' }
  end

  it 'logs UniversalEvent with correct schema on failure' do
    job = { 'args' => [{ id: 42 }], 'jid' => 'jid3', 'queue' => 'default' }
    expect(EzlogsRubyAgent.writer).to receive(:log).with(instance_of(EzlogsRubyAgent::UniversalEvent))
    expect do
      tracker.call(worker, job, queue) { raise 'fail!' }
    end.to raise_error('fail!')
  end

  it 'extracts actor as a hash' do
    job = { 'args' => [{}], 'jid' => 'jid4', 'queue' => 'default' }
    allow(EzlogsRubyAgent::ActorExtractor).to receive(:extract_actor).and_return({ type: 'user', id: 'u1',
                                                                                   email: 'e@x.com' })
    expect(EzlogsRubyAgent.writer).to receive(:log) do |event|
      expect(event.actor).to eq({ type: 'user', id: 'u1', email: 'e@x.com' })
    end
    tracker.call(worker, job, queue) { 'ok' }
  end

  it 'sets subject with job id and queue' do
    job = { 'args' => [{ id: 99 }], 'jid' => 'jid5', 'queue' => 'critical' }
    expect(EzlogsRubyAgent.writer).to receive(:log) do |event|
      expect(event.subject[:type]).to eq('job')
      expect(event.subject[:id]).to eq('jid5')
      expect(event.subject[:queue]).to eq('critical')
      expect(event.subject[:resource]).to eq(99)
    end
    tracker.call(worker, job, queue) { 'ok' }
  end

  it 'handles missing correlation gracefully' do
    job = { 'args' => [{}], 'jid' => 'jid6', 'queue' => 'default' }
    expect do
      tracker.call(worker, job, queue) { 'ok' }
    end.not_to raise_error
  end

  it 'creates UniversalEvent with correct schema' do
    event = tracker.build_event(job_hash)
    expect(event).to be_a(EzlogsRubyAgent::UniversalEvent)
    expect(event.event_type).to eq('sidekiq.job')
    expect(event.action).to eq('enqueue')
    expect(event.actor[:type]).to eq('Job')
    expect(event.actor[:id]).to eq('abc123')
    expect(event.payload[:queue]).to eq('default')
  end

  it 'inherits correlation context' do
    event = tracker.build_event(job_hash)
    expect(event.correlation_context).to eq(context)
  end

  it 'handles missing job id gracefully' do
    job_hash.delete('jid')
    event = tracker.build_event(job_hash)
    expect(event.actor[:id]).to be_nil
  end

  it 'extracts job args' do
    event = tracker.build_event(job_hash)
    expect(event.payload[:args]).to eq(job_args)
  end

  it 'logs event on perform' do
    expect(EzlogsRubyAgent.writer).to receive(:log).with(instance_of(EzlogsRubyAgent::UniversalEvent))
    tracker.track(job_hash)
  end
end
