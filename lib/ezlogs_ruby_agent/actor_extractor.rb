module EzlogsRubyAgent
  module ActorExtractor
    def self.extract_actor(resource) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      if defined?(current_user)
        current_user&.email || current_user&.id
      elsif resource.respond_to?(:user) && resource.user
        resource.user&.email || resource.user&.id
      else
        'System'
      end
    end
  end
end
