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

  describe '.extract_actor' do
    context 'with custom actor extractor configured' do
      before do
        EzlogsRubyAgent.configure do |config|
          config.actor_extractor = lambda { |resource|
            if resource.is_a?(Hash) && resource['HTTP_X_CUSTOM_USER_ID']
              {
                type: 'custom_user',
                id: resource['HTTP_X_CUSTOM_USER_ID'],
                email: resource['HTTP_X_CUSTOM_USER_EMAIL'],
                role: 'admin'
              }
            elsif resource.is_a?(Hash) && resource['HTTP_X_API_KEY']
              {
                type: 'api_user',
                id: 'api_123',
                name: 'API User',
                permissions: %w[read write]
              }
            end
          }
        end
      end

      after do
        EzlogsRubyAgent.configure do |config|
          config.actor_extractor = nil
        end
      end

      it 'uses custom extractor for custom user header' do
        resource = {
          'HTTP_X_CUSTOM_USER_ID' => 'user_123',
          'HTTP_X_CUSTOM_USER_EMAIL' => 'test@example.com'
        }

        actor = described_class.extract_actor(resource)

        expect(actor).to eq({
          type: 'custom_user',
          id: 'user_123',
          email: 'test@example.com',
          role: 'admin'
        })
      end

      it 'uses custom extractor for API key' do
        resource = {
          'HTTP_X_API_KEY' => 'api_key_123'
        }

        actor = described_class.extract_actor(resource)

        expect(actor).to eq({
          type: 'api_user',
          id: 'api_123',
          name: 'API User',
          permissions: %w[read write]
        })
      end

      it 'falls back to default extraction when custom extractor returns nil' do
        resource = { 'HTTP_USER_AGENT' => 'Mozilla/5.0' }

        # Mock current_user to return a user
        allow(described_class).to receive(:get_current_user).and_return(
          double(id: 456, email: 'fallback@example.com')
        )

        actor = described_class.extract_actor(resource)

        expect(actor).to eq({
          type: 'user',
          id: 456,
          email: 'fallback@example.com'
        })
      end
    end

    context 'without custom actor extractor' do
      before do
        EzlogsRubyAgent.configure do |config|
          config.actor_extractor = nil
        end
      end

      it 'uses default extraction' do
        resource = { 'HTTP_USER_AGENT' => 'Mozilla/5.0' }

        # Mock current_user to return a user
        allow(described_class).to receive(:get_current_user).and_return(
          double(id: 789, email: 'default@example.com')
        )

        actor = described_class.extract_actor(resource)

        expect(actor).to eq({
          type: 'user',
          id: 789,
          email: 'default@example.com'
        })
      end
    end

    context 'when custom extractor raises an error' do
      before do
        EzlogsRubyAgent.configure do |config|
          config.actor_extractor = lambda { |resource|
            raise 'Custom extractor error'
          }
        end
      end

      after do
        EzlogsRubyAgent.configure do |config|
          config.actor_extractor = nil
        end
      end

      it 'falls back to default extraction and logs warning' do
        resource = { 'HTTP_USER_AGENT' => 'Mozilla/5.0' }

        # Mock current_user to return a user
        allow(described_class).to receive(:get_current_user).and_return(
          double(id: 999, email: 'fallback@example.com')
        )

        expect { described_class.extract_actor(resource) }.to output(/failed to extract actor/).to_stderr

        actor = described_class.extract_actor(resource)

        expect(actor).to eq({
          type: 'user',
          id: 999,
          email: 'fallback@example.com'
        })
      end
    end
  end

  describe '.get_current_user' do
    context 'when Current.user is available' do
      before do
        @current_user = double(id: 456, email: 'current@example.com')
        stub_const('Current', double(user: @current_user))
      end

      it 'returns Current.user' do
        user = described_class.get_current_user
        expect(user).to eq(@current_user)
      end
    end

    context 'when RequestStore is available' do
      before do
        @current_user = double(id: 789, email: 'request@example.com')
        stub_const('RequestStore', double(store: { current_user: @current_user }))
      end

      it 'returns user from RequestStore' do
        user = described_class.get_current_user
        expect(user).to eq(@current_user)
      end
    end

    context 'when Thread.current has current_user' do
      before do
        @current_user = double(id: 101, email: 'thread@example.com')
        allow(Thread.current).to receive(:[]).with(:current_user).and_return(@current_user)
      end

      it 'returns user from Thread.current' do
        user = described_class.get_current_user
        expect(user).to eq(@current_user)
      end
    end

    context 'when no user is available' do
      it 'returns nil' do
        user = described_class.get_current_user
        expect(user).to be_nil
      end
    end
  end

  describe '.extract_user_from_resource' do
    context 'when resource has user method' do
      it 'returns resource.user' do
        user = double(id: 123, email: 'user@example.com')
        resource = double(user: user)

        result = described_class.extract_user_from_resource(resource)
        expect(result).to eq(user)
      end
    end

    context 'when resource has current_user method' do
      it 'returns resource.current_user' do
        user = double(id: 456, email: 'current@example.com')
        resource = double(current_user: user)

        result = described_class.extract_user_from_resource(resource)
        expect(result).to eq(user)
      end
    end

    context 'when resource has neither user nor current_user' do
      it 'returns nil' do
        resource = double

        result = described_class.extract_user_from_resource(resource)
        expect(result).to be_nil
      end
    end
  end

  describe '.extract_user_id' do
    context 'when user has id method' do
      it 'returns user.id' do
        user = double(id: 123)
        result = described_class.extract_user_id(user)
        expect(result).to eq(123)
      end
    end

    context 'when user does not have id method' do
      it 'returns user.to_s' do
        user = double(to_s: 'user_456')
        result = described_class.extract_user_id(user)
        expect(result).to eq('user_456')
      end
    end
  end

  describe '.extract_user_email' do
    context 'when user has email method' do
      it 'returns user.email' do
        user = double(email: 'test@example.com')
        result = described_class.extract_user_email(user)
        expect(result).to eq('test@example.com')
      end
    end

    context 'when user does not have email method' do
      it 'returns nil' do
        user = double
        result = described_class.extract_user_email(user)
        expect(result).to be_nil
      end
    end
  end
end
