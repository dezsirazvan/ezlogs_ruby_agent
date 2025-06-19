module EzlogsRubyAgent
  module ActorExtractor
    def self.extract_actor(resource) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      # Try to get current user from various contexts
      current_user = get_current_user

      if current_user
        current_user.respond_to?(:email) ? current_user.email : current_user.id
      elsif resource.respond_to?(:user) && resource.user
        resource.user.respond_to?(:email) ? resource.user.email : resource.user.id
      elsif resource.respond_to?(:current_user) && resource.current_user
        resource.current_user.respond_to?(:email) ? resource.current_user.email : resource.current_user.id
      else
        'System'
      end
    rescue StandardError => e
      warn "[Ezlogs] failed to extract actor: #{e.message}"
      'System'
    end

    def self.get_current_user
      # Try different ways to get current user
      if defined?(current_user) && current_user
        current_user
      elsif defined?(Current) && Current.respond_to?(:user)
        Current.user
      elsif defined?(RequestStore) && RequestStore.store[:current_user]
        RequestStore.store[:current_user]
      elsif defined?(Thread.current) && Thread.current[:current_user]
        Thread.current[:current_user]
      end
    rescue StandardError
      nil
    end
  end
end
