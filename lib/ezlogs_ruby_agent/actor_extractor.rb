module EzlogsRubyAgent
  module ActorExtractor
    def self.extract_actor(resource)
      user = get_current_user || extract_user_from_resource(resource)
      if user
        {
          type: 'user',
          id: extract_user_id(user),
          email: extract_user_email(user)
        }.compact
      else
        { type: 'system', id: 'system' }
      end
    rescue StandardError => e
      warn "[Ezlogs] failed to extract actor: #{e.message}"
      { type: 'system', id: 'system' }
    end

    def self.get_current_user
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

    def self.extract_user_from_resource(resource)
      if resource.respond_to?(:user) && resource.user
        resource.user
      elsif resource.respond_to?(:current_user) && resource.current_user
        resource.current_user
      end
    end

    def self.extract_user_id(user)
      user.respond_to?(:id) ? user.id : user.to_s
    end

    def self.extract_user_email(user)
      user.respond_to?(:email) ? user.email : nil
    end
  end
end
