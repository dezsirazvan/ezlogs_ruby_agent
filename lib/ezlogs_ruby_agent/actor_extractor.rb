module EzlogsRubyAgent
  class ActorExtractor
    def self.extract_actor(request = nil)
      actor = find_actor_from_current || 
              find_actor_from_devise_current_user ||
              find_actor_from_headers(request) || 
              find_actor_from_session ||
      actor ||= 'system'
      actor
    end

    private

    def self.find_actor_from_current
      Current.user&.id if Current.respond_to?(:user) && Current.user
    end

    def self.find_actor_from_devise_current_user
      return nil unless request && request.env['warden']

      user = request.env['warden'].user
      user&.id || current_user&.id  
    end

    def self.find_actor_from_headers(request)
      return nil unless request

      actor_id = request.headers['Actor'] || request.headers['User-Id']
      actor_id
    end

    def self.find_actor_from_session
      if defined?(session) && session[:user_id]
        session[:user_id]
      else
        nil
      end
    end
  end
end
