require 'spec_helper'

RSpec.describe EzlogsRubyAgent::ActorExtractor do
  let(:extractor) { described_class }

  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'test-app'
      config.environment = 'test'
    end
  end

  after do
    # Clean up thread-local storage
    Thread.current[:current_user] = nil
  end

  it 'extracts from Current.user' do
    user = double('User', id: 123, email: 'user@example.com')
    stub_const('Current', double('Current', user: user))
    expect(described_class.extract_actor(nil)).to include(:type, :id)
  end

  it 'extracts from RequestStore' do
    user = double('User', id: 123, email: 'user@example.com')
    stub_const('RequestStore', double('RequestStore', store: { current_user: user }))
    expect(described_class.extract_actor(nil)).to include(:type, :id)
  end

  it 'extracts from Thread.current' do
    user = double('User', id: 123, email: 'user@example.com')
    Thread.current[:current_user] = user
    expect(described_class.extract_actor(nil)).to include(:type, :id)
  end

  it 'extracts from resource with user method' do
    user = double('User', id: 123, email: 'user@example.com')
    resource = double('Resource', user: user)
    result = extractor.extract_actor(resource)
    expect(result).to include(:type, :id, :email)
    expect(result[:type]).to eq('user')
    expect(result[:id]).to eq(123)
    expect(result[:email]).to eq('user@example.com')
  end

  it 'extracts from resource with current_user method' do
    user = double('User', id: 123, email: 'user@example.com')
    resource = double('Resource', current_user: user)
    result = extractor.extract_actor(resource)
    expect(result).to include(:type, :id, :email)
    expect(result[:type]).to eq('user')
    expect(result[:id]).to eq(123)
    expect(result[:email]).to eq('user@example.com')
  end

  it 'returns system actor when no user found' do
    result = extractor.extract_actor(nil)
    expect(result).to eq({ type: 'system', id: 'system' })
  end

  it 'handles user without email' do
    user_without_email = double('User', id: 456)
    resource = double('Resource', user: user_without_email)
    result = extractor.extract_actor(resource)
    expect(result).to include(:type, :id)
    expect(result[:email]).to be_nil
  end

  it 'handles user without id' do
    user_without_id = double('User', email: 'test@example.com')
    allow(user_without_id).to receive(:to_s).and_return('User')
    resource = double('Resource', user: user_without_id)
    result = extractor.extract_actor(resource)
    expect(result).to include(:type, :id, :email)
    expect(result[:id]).to eq('User')
  end

  it 'handles nil user gracefully' do
    resource = double('Resource', user: nil)
    result = extractor.extract_actor(resource)
    expect(result).to eq({ type: 'system', id: 'system' })
  end

  it 'handles resource without user methods' do
    resource = double('Resource')
    result = extractor.extract_actor(resource)
    expect(result).to eq({ type: 'system', id: 'system' })
  end

  it 'handles exceptions gracefully' do
    resource = double('Resource')
    allow(resource).to receive(:user).and_raise(StandardError, 'test error')
    result = extractor.extract_actor(resource)
    expect(result).to eq({ type: 'system', id: 'system' })
  end
end
