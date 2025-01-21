# frozen_string_literal: true

RSpec.describe EzlogsRubyAgent do
  describe '.configure' do
    it 'yields the config block if a block is given' do
      EzlogsRubyAgent.configure do |config|
        config.batch_size = 10
      end
      expect(EzlogsRubyAgent.config.batch_size).to eq(10)
    end

    it 'does not yield the config block if no block is given' do
      EzlogsRubyAgent.instance_variable_set(:@config, nil)

      expect(EzlogsRubyAgent.config.batch_size).to eq(100)
    end

    it 'sets custom configuration using the block' do
      EzlogsRubyAgent.configure do |config|
        config.endpoint_url = 'https://example.com'
        config.models_to_track = %w[User Order]
      end

      expect(EzlogsRubyAgent.config.endpoint_url).to eq('https://example.com')
      expect(EzlogsRubyAgent.config.models_to_track).to eq(%w[User Order])
    end
  end

  describe '.config' do
    it 'returns the current configuration object' do
      expect(EzlogsRubyAgent.config).to be_a(EzlogsRubyAgent::Configuration)
    end

    it 'returns the same instance of config every time' do
      first_instance = EzlogsRubyAgent.config
      second_instance = EzlogsRubyAgent.config

      expect(first_instance).to eq(second_instance)
      expect(first_instance.object_id).to eq(second_instance.object_id)
    end
  end
end
