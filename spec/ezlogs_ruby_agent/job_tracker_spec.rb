require 'spec_helper'

RSpec.describe EzlogsRubyAgent::JobTracker do
  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
      config.included_resources = []
      config.excluded_resources = []
    end

    # Enable debug mode to capture events
    EzlogsRubyAgent.debug_mode = true
    EzlogsRubyAgent.clear_captured_events
  end

  after do
    EzlogsRubyAgent.debug_mode = false
    EzlogsRubyAgent.clear_captured_events
  end

  it 'restores correlation from job args' do
    job_class = Class.new do
      def self.name = 'TestJob'
      def job_id = 'job_123'
      def queue_name = 'default'
      def retry_count = 2
      def priority = 'high'
      def perform(*_args) = 'done'
    end
    job_class.include(EzlogsRubyAgent::JobTracker)
    job = job_class.new

    args = [{ '_correlation_data' => { correlation_id: 'corr_abc' } }]
    expect(EzlogsRubyAgent::CorrelationManager).to receive(:restore_context).with(args.first['_correlation_data'])
    allow(job).to receive(:super).and_return('done')
    job.perform(*args)
  end

  it 'logs UniversalEvent with correct schema on success' do
    job_class = Class.new do
      def self.name = 'TestJob'
      def job_id = 'job_123'
      def queue_name = 'default'
      def retry_count = 2
      def priority = 'high'
      def perform(*_args) = 'done'
    end
    job_class.include(EzlogsRubyAgent::JobTracker)
    job = job_class.new

    allow(job).to receive(:super).and_return('done')
    job.perform({})
    events = EzlogsRubyAgent.captured_events
    expect(events).to have_event_count(2) # started and completed
    expect(events.first[:event][:event_type]).to eq('job.execution')
    expect(events.last[:event][:event_type]).to eq('job.execution')
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
    error_job_class.include(EzlogsRubyAgent::JobTracker)
    error_job = error_job_class.new

    expect { error_job.perform({}) }.to raise_error('fail!')
    events = EzlogsRubyAgent.captured_events
    expect(events).to have_event_count(2) # started and failed
    expect(events.first[:event][:event_type]).to eq('job.execution')
    expect(events.last[:event][:event_type]).to eq('job.execution')
    expect(events.last[:event][:metadata][:status]).to eq('failed')
  end

  it 'extracts actor as a hash' do
    job_class = Class.new do
      def self.name = 'TestJob'
      def job_id = 'job_123'
      def queue_name = 'default'
      def retry_count = 2
      def priority = 'high'
      def perform(*_args) = 'done'
    end
    job_class.include(EzlogsRubyAgent::JobTracker)
    job = job_class.new

    allow(EzlogsRubyAgent::ActorExtractor).to receive(:extract_actor).and_return({ type: 'user', id: 'u1' })
    allow(job).to receive(:super).and_return('done')
    job.perform({})
    events = EzlogsRubyAgent.captured_events
    expect(events).to have_event_count(2) # started and completed
    expect(events.first[:event][:actor]).to eq({ type: 'user', id: 'u1' })
    expect(events.last[:event][:actor]).to eq({ type: 'user', id: 'u1' })
  end

  it 'sets subject with job id and queue' do
    job_class = Class.new do
      def self.name = 'TestJob'
      def job_id = 'job_123'
      def queue_name = 'default'
      def retry_count = 2
      def priority = 'high'
      def perform(*_args) = 'done'
    end
    job_class.include(EzlogsRubyAgent::JobTracker)
    job = job_class.new

    allow(job).to receive(:super).and_return('done')
    job.perform({})
    events = EzlogsRubyAgent.captured_events
    expect(events).to have_event_count(2) # started and completed
    expect(events.first[:event][:subject][:type]).to eq('job')
    expect(events.first[:event][:subject][:id]).to eq('TestJob')
    expect(events.first[:event][:subject][:queue]).to eq('default')
    expect(events.last[:event][:subject][:type]).to eq('job')
    expect(events.last[:event][:subject][:id]).to eq('TestJob')
    expect(events.last[:event][:subject][:queue]).to eq('default')
  end

  it 'handles missing correlation gracefully' do
    job_class = Class.new do
      def self.name = 'TestJob'
      def job_id = 'job_123'
      def queue_name = 'default'
      def retry_count = 2
      def priority = 'high'
      def perform(*_args) = 'done'
    end
    job_class.include(EzlogsRubyAgent::JobTracker)
    job = job_class.new

    expect do
      allow(job).to receive(:super).and_return('done')
      job.perform({})
    end.not_to raise_error
  end

  it 'includes retry count and priority in metadata' do
    job_class = Class.new do
      def self.name = 'TestJob'
      def job_id = 'job_123'
      def queue_name = 'default'
      def retry_count = 2
      def priority = 'high'
      def perform(*_args) = 'done'
    end
    job_class.include(EzlogsRubyAgent::JobTracker)
    job = job_class.new

    allow(job).to receive(:super).and_return('done')
    job.perform({})
    events = EzlogsRubyAgent.captured_events
    expect(events).to have_event_count(2) # started and completed
    expect(events.first[:event][:metadata][:retry_count]).to eq(0)
    expect(events.first[:event][:metadata][:priority]).to eq('normal')
    expect(events.last[:event][:metadata][:retry_count]).to eq(0)
    expect(events.last[:event][:metadata][:priority]).to eq('normal')
  end
end
