require 'spec_helper'

RSpec.describe EzlogsRubyAgent::HttpTracker do
  let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:tracker) { described_class.new(app) }

  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
      config.included_resources = []
      config.excluded_resources = []
    end

    # Mock the writer to capture events synchronously
    allow(EzlogsRubyAgent.writer).to receive(:log) do |event|
      @captured_events ||= []
      @captured_events << event
    end
  end

  after do
    @captured_events = nil
  end

  it 'logs UniversalEvent for HTTP request' do
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/users/1',
      'QUERY_STRING' => '',
      'HTTP_X_REQUEST_ID' => 'req_1',
      'HTTP_X_SESSION_ID' => 'sess_1',
      'HTTP_USER_AGENT' => 'TestAgent',
      'REMOTE_ADDR' => '127.0.0.1',
      'rack.input' => StringIO.new('')
    }
    tracker.call(env)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first).to be_a(EzlogsRubyAgent::UniversalEvent)
  end

  it 'extracts actor as a hash' do
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/users/1',
      'rack.input' => StringIO.new('')
    }
    allow(EzlogsRubyAgent::ActorExtractor).to receive(:extract_actor).and_return({ type: 'user', id: 'u1' })
    tracker.call(env)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first.actor).to eq({ type: 'user', id: 'u1' })
  end

  it 'extracts subject from path' do
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/users/1',
      'rack.input' => StringIO.new('')
    }
    tracker.call(env)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first.subject[:type]).to eq('user')
    expect(@captured_events.first.subject[:id]).to eq('1')
  end

  it 'handles GraphQL requests specially' do
    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/graphql',
      'rack.input' => StringIO.new('{"operationName":"TestOp","query":"query { user { id } }"}')
    }
    tracker.call(env)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first.subject[:type]).to eq('graphql')
    expect(@captured_events.first.subject[:id]).to eq('TestOp')
    expect(@captured_events.first.subject[:operation]).to eq('query')
  end

  it 'handles error responses' do
    error_app = ->(_env) { [500, {}, ['Internal Error']] }
    tracker = described_class.new(error_app)
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/fail',
      'rack.input' => StringIO.new('')
    }
    tracker.call(env)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first.metadata[:status]).to eq(500)
    expect(@captured_events.first.metadata[:error]).to be_present
  end

  it 'sanitizes params' do
    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/users',
      'rack.input' => StringIO.new('password=secret&email=test@example.com')
    }
    tracker.call(env)
    expect(@captured_events).to have_event_count(1)
    expect(@captured_events.first).to be_a(EzlogsRubyAgent::UniversalEvent)
  end

  it 'handles missing path gracefully' do
    env = { 'REQUEST_METHOD' => 'GET', 'rack.input' => StringIO.new('') }
    expect do
      tracker.call(env)
    end.not_to raise_error
  end
end
