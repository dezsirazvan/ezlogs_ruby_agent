require 'spec_helper'
require 'ezlogs_ruby_agent/http_tracker'
require 'ezlogs_ruby_agent/event_queue'
require 'active_support/all'

RSpec.describe EzlogsRubyAgent::HttpTracker, type: :request do
  let(:app) { double("app", call: [200, {}, "response"]) }
  let(:http_tracker) { EzlogsRubyAgent::HttpTracker.new(app) }
  let(:env) do
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/models/1",
      "rack.input" => StringIO.new("param1=value1&param2=value2")
    }
  end

  before do
    # Mock the EventQueue to avoid actually adding to the queue during tests
    allow(EzlogsRubyAgent::EventQueue).to receive(:add)
    
    # Set configuration for models to track
    EzlogsRubyAgent.config.models_to_track = ['Model']
    EzlogsRubyAgent.config.exclude_models = []
  end

  describe '#call' do
    it 'generates a request ID and stores it in the thread' do
      expect(SecureRandom).to receive(:uuid).and_return("request-id")
      
      http_tracker.call(env)
      
      expect(Thread.current[:ezlogs_request_id]).to eq("request-id")
    end

    it 'adds an event to the EventQueue for trackable requests' do
      time = Time.current
      allow(Time).to receive(:current).and_return(time)
      allow(SecureRandom).to receive(:uuid).and_return("request-id")

      allow(EzlogsRubyAgent::EventQueue).to receive(:add)
      
      http_tracker.call(env)
      
      expect(EzlogsRubyAgent::EventQueue).to have_received(:add).with({
        type: "http_request",
        method: "GET",
        path: "/models/1",
        params: {"param1" => "value1", "param2" => "value2"},
        status: 200,
        request_id: "request-id",
        timestamp: time,
        response_time: 0.0
      })
    end

    it 'adds X-Request-ID header to the response' do
      allow(SecureRandom).to receive(:uuid).and_return("request-id")
      status, headers, response = http_tracker.call(env)
      
      expect(headers["X-Request-ID"]).to eq("request-id")
    end

    it 'does not log events for untrackable requests' do
      EzlogsRubyAgent.config.models_to_track = ['UntrackableModel']

      expect(EzlogsRubyAgent::EventQueue).not_to receive(:add)

      http_tracker.call(env)
    end

    it 'logs events for trackable models' do
      time = Time.current
      allow(Time).to receive(:current).and_return(time)
      allow(SecureRandom).to receive(:uuid).and_return("request-id")
      EzlogsRubyAgent.config.models_to_track = ['Model']
      
      expect(EzlogsRubyAgent::EventQueue).to receive(:add).with({
        type: "http_request",
        method: "GET",
        path: "/models/1",
        params: {"param1" => "value1", "param2" => "value2"},
        request_id: "request-id",
        status: 200,
        response_time: 0.0,
        timestamp: time
      })
      
      http_tracker.call(env)
    end
  end
end
