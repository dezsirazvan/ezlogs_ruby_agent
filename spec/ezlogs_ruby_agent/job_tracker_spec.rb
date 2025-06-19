require 'spec_helper'

RSpec.describe EzlogsRubyAgent::JobTracker do
  let(:job_class) do
    Class.new do
      def self.name = 'TestJob'
      def job_id = 'job_123'
      def queue_name = 'default'
      def retry_count = 2
      def priority = 'high'
      def perform(*_args) = 'done'
    end
  end
  let(:job) { job_class.new }

  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
      config.resources_to_track = []
      config.exclude_resources = []
    end

    # Mock the writer to capture events synchronously
    allow(EzlogsRubyAgent.writer).to receive(:log) do |event|
      @captured_events ||= []
      @captured_events << event
    end

    job.extend(EzlogsRubyAgent::JobTracker)
  end

  after do
    @captured_events = nil
  end

  it 'restores correlation from job args' do
    args = [{ '_correlation_data' => { correlation_id: 'corr_abc' } }]
    expect(EzlogsRubyAgent::CorrelationManager).to receive(:restore_context).with(args.first['_correlation_data'])
    allow(job).to receive(:super).and_return('done')
    job.perform(*args)
  end

  it 'logs UniversalEvent with correct schema on success' do
    allow(job).to receive(:super).and_return('done')
    job.perform({})
    expect(@captured_events).to have_event_count(2) # started and completed
    expect(@captured_events.first).to be_a(EzlogsRubyAgent::UniversalEvent)
    expect(@captured_events.last).to be_a(EzlogsRubyAgent::UniversalEvent)
  end

  it 'logs UniversalEvent with correct schema on failure' do
    # Create a job class that raises an error
    error_job_class = Class.new do
      def self.name = 'TestJob'
      def job_id = 'job_123'
      def queue_name = 'default'
      def retry_count = 2
      def priority = 'high'

      def perform(*_args)
        raise 'fail!'
      end
    end
    error_job = error_job_class.new
    error_job.extend(EzlogsRubyAgent::JobTracker)

    expect { error_job.perform({}) }.to raise_error('fail!')
    expect(@captured_events).to have_event_count(2) # started and failed
    expect(@captured_events.first).to be_a(EzlogsRubyAgent::UniversalEvent)
    expect(@captured_events.last).to be_a(EzlogsRubyAgent::UniversalEvent)
    expect(@captured_events.last.metadata[:status]).to eq('failed')
  end

  it 'extracts actor as a hash' do
    allow(EzlogsRubyAgent::ActorExtractor).to receive(:extract_actor).and_return({ type: 'user', id: 'u1' })
    allow(job).to receive(:super).and_return('done')
    job.perform({})
    expect(@captured_events).to have_event_count(2) # started and completed
    expect(@captured_events.first.actor).to eq({ type: 'user', id: 'u1' })
    expect(@captured_events.last.actor).to eq({ type: 'user', id: 'u1' })
  end

  it 'sets subject with job id and queue' do
    allow(job).to receive(:super).and_return('done')
    job.perform({})
    expect(@captured_events).to have_event_count(2) # started and completed
    expect(@captured_events.first.subject[:type]).to eq('job')
    expect(@captured_events.first.subject[:id]).to match(/^job_/)
    expect(@captured_events.first.subject[:queue]).to eq('default')
    expect(@captured_events.last.subject[:type]).to eq('job')
    expect(@captured_events.last.subject[:id]).to match(/^job_/)
    expect(@captured_events.last.subject[:queue]).to eq('default')
  end

  it 'handles missing correlation gracefully' do
    expect do
      allow(job).to receive(:super).and_return('done')
      job.perform({})
    end.not_to raise_error
  end

  it 'includes retry count and priority in metadata' do
    allow(job).to receive(:super).and_return('done')
    job.perform({})
    expect(@captured_events).to have_event_count(2) # started and completed
    expect(@captured_events.first.metadata[:retry_count]).to eq(2)
    expect(@captured_events.first.metadata[:priority]).to eq('high')
    expect(@captured_events.last.metadata[:retry_count]).to eq(2)
    expect(@captured_events.last.metadata[:priority]).to eq('high')
  end
end
