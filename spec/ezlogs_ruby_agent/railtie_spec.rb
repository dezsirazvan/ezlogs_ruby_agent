# # frozen_string_literal: true

# require 'spec_helper'
# require 'rails'
# require 'ezlogs_ruby_agent/railtie'

# class ActiveRecord
#   class Base; end
# end

# class ApplicationJob; end

# RSpec.describe EzlogsRubyAgent::Railtie do
#   let(:app) { double('Rails::Application', config: double('Configuration')) }

#   describe 'initialization' do
#     it 'configures EzlogsRubyAgent with default settings' do
#       Rails.application = app
#       EzlogsRubyAgent::Railtie.instance.run_initializers

#       config = EzlogsRubyAgent.config
#       expect(config.capture_http).to be true
#       expect(config.capture_callbacks).to be true
#       expect(config.capture_jobs).to be true
#       expect(config.models_to_track).to eq([])
#       expect(config.exclude_models).to eq([])
#     end
#   end
# end
