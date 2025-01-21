RSpec.describe EzlogsRubyAgent::Configuration do
  subject(:config) { EzlogsRubyAgent::Configuration.new }

  describe '#initialize' do
    it 'sets default values for all attributes' do
      expect(config.capture_http).to be true
      expect(config.capture_callbacks).to be true
      expect(config.capture_jobs).to be true
      expect(config.models_to_track).to eq([])
      expect(config.exclude_models).to eq([])
      expect(config.batch_size).to eq(100)
      expect(config.endpoint_url).to eq('https://api.ezlogs.com/events')
    end
  end

  describe 'attribute setters and getters' do
    it 'allows setting and getting capture_http' do
      config.capture_http = false
      expect(config.capture_http).to be false
    end

    it 'allows setting and getting capture_callbacks' do
      config.capture_callbacks = false
      expect(config.capture_callbacks).to be false
    end

    it 'allows setting and getting capture_jobs' do
      config.capture_jobs = false
      expect(config.capture_jobs).to be false
    end

    it 'allows setting and getting models_to_track' do
      config.models_to_track = ['User', 'Order']
      expect(config.models_to_track).to eq(['User', 'Order'])
    end

    it 'allows setting and getting exclude_models' do
      config.exclude_models = ['Admin']
      expect(config.exclude_models).to eq(['Admin'])
    end

    it 'allows setting and getting batch_size' do
      config.batch_size = 200
      expect(config.batch_size).to eq(200)
    end

    it 'allows setting and getting endpoint_url' do
      config.endpoint_url = 'https://new-api.com/events'
      expect(config.endpoint_url).to eq('https://new-api.com/events')
    end
  end
end
