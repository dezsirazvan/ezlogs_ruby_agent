require 'spec_helper'

RSpec.describe EzlogsRubyAgent::CallbacksTracker do
  let(:model_class) do
    Class.new do
      attr_accessor :id, :attributes, :previous_changes, :errors, :table_name

      def self.name = 'User'
      def self.table_name = 'users'
      def model_name = OpenStruct.new(singular: 'user')

      def initialize
        @id = 1
        @attributes = { 'id' => 1, 'name' => 'Jane' }
        @previous_changes = { 'name' => ['', 'Jane'] }
        @errors = []
        @table_name = 'users'
      end

      # Add Rails compatibility methods
      def saved_changes
        @previous_changes
      end

      def saved_attributes
        @attributes
      end

      def attributes_was
        @attributes
      end
    end
  end
  let(:model) { model_class.new }

  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
      config.resources_to_track = []
      config.exclude_resources = []
    end

    # Mock the writer to capture events synchronously
    allow(EzlogsRubyAgent.writer).to receive(:log) do |event|
      # Store the event for testing
      @captured_events ||= []
      @captured_events << event
    end

    model.extend(EzlogsRubyAgent::CallbacksTracker)
  end

  after do
    @captured_events = nil
  end

  it 'logs UniversalEvent on create' do
    model.send(:log_create_event)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first).to be_a(EzlogsRubyAgent::UniversalEvent)
  end

  it 'logs UniversalEvent on update' do
    model.send(:log_update_event)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first).to be_a(EzlogsRubyAgent::UniversalEvent)
  end

  it 'logs UniversalEvent on destroy' do
    model.send(:log_destroy_event)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first).to be_a(EzlogsRubyAgent::UniversalEvent)
  end

  it 'inherits correlation from context' do
    EzlogsRubyAgent.start_flow('user_flow', 'user_1')
    expect(EzlogsRubyAgent.writer).to receive(:log) do |event|
      expect(event.correlation[:flow_id]).to eq('flow_user_flow_user_1')
    end
    model.send(:log_create_event)
  end

  it 'extracts actor as a hash' do
    allow(EzlogsRubyAgent::ActorExtractor).to receive(:extract_actor).and_return({ type: 'user', id: 1 })
    model.send(:log_create_event)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first.actor).to eq({ type: 'user', id: 1 })
  end

  it 'handles errors gracefully' do
    allow(EzlogsRubyAgent::ActorExtractor).to receive(:extract_actor).and_raise('fail')
    expect do
      model.send(:log_create_event)
    end.not_to raise_error
  end

  it 'adds validation errors to metadata' do
    model.errors = double('Errors', any?: true, full_messages: ['Invalid'])
    model.send(:log_create_event)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first.metadata[:validation_errors]).to include('Invalid')
  end

  it 'adds bulk operation context if present' do
    allow(model).to receive(:bulk_operation?).and_return(true)
    allow(model).to receive(:bulk_size).and_return(5)
    model.send(:log_create_event)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first.metadata[:bulk_operation]).to be true
    expect(@captured_events.first.metadata[:bulk_size]).to eq(5)
  end
end
