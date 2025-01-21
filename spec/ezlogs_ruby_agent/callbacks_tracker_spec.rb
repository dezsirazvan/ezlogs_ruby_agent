# frozen_string_literal: true

require 'spec_helper'
require 'active_support/concern'
require 'ezlogs_ruby_agent/event_queue'
require 'active_record'
require 'ezlogs_ruby_agent/callbacks_tracker'

RSpec.describe EzlogsRubyAgent::CallbacksTracker, type: :module do
  before do
    schema_cache_double = double(
      'schema_cache',
      columns_hash: {},
      data_source_exists?: true
    )
    connection_double = double('connection',
                               established?: true,
                               schema_cache: schema_cache_double,
                               tables: [],
                               columns: [],
                               execute: nil)
    allow(ActiveRecord::Base).to receive(:connection).and_return(connection_double)

    class DummyModel < ActiveRecord::Base # rubocop:disable Lint/ConstantDefinitionInBlock
      self.table_name = nil

      include EzlogsRubyAgent::CallbacksTracker
    end
  end

  after do
    Object.send(:remove_const, :DummyModel)
  end

  describe '#trackable_model?' do
    let(:dummy_model_class) { DummyModel }

    it 'returns true if the model is in models_to_track' do
      EzlogsRubyAgent.config.models_to_track = ['DummyModel']

      model = dummy_model_class.new

      expect(model.send(:trackable_model?)).to be true
    end

    it 'returns false if the model is in exclude_models' do
      EzlogsRubyAgent.config.exclude_models = ['DummyModel']

      model = dummy_model_class.new

      expect(model.send(:trackable_model?)).to be false
    end

    it 'returns true if models_to_track is empty' do
      EzlogsRubyAgent.config.models_to_track = []
      EzlogsRubyAgent.config.exclude_models = []

      model = dummy_model_class.new

      expect(model.send(:trackable_model?)).to be true
    end
  end

  describe 'callbacks' do
    let(:dummy_model_class) { DummyModel }

    it 'calls log_create_event on after_create callback' do
      allow(EzlogsRubyAgent::EventQueue).to receive(:add)

      EzlogsRubyAgent.config.models_to_track = ['DummyModel']
      model = dummy_model_class.new
      model.run_callbacks(:create) { true }

      expect(EzlogsRubyAgent::EventQueue).to have_received(:add).with(hash_including({
        action: 'create',
        model: 'DummyModel'
      }))
    end

    it 'calls log_update_event on after_update callback' do
      allow(EzlogsRubyAgent::EventQueue).to receive(:add)

      EzlogsRubyAgent.config.models_to_track = ['DummyModel']
      model = dummy_model_class.new
      model.run_callbacks(:update) { true }

      expect(EzlogsRubyAgent::EventQueue).to have_received(:add).with(hash_including({
        action: 'update',
        model: 'DummyModel'
      }))
    end

    it 'calls log_destroy_event on after_destroy callback' do
      allow(EzlogsRubyAgent::EventQueue).to receive(:add)

      EzlogsRubyAgent.config.models_to_track = ['DummyModel']
      model = dummy_model_class.new
      model.run_callbacks(:destroy) { true }

      expect(EzlogsRubyAgent::EventQueue).to have_received(:add).with(hash_including({
        action: 'destroy',
        model: 'DummyModel'
      }))
    end
  end
end
