module EzlogsRubyAgent
  class HttpTracker
    def initialize(app)
      @app = app
    end

    def call(env)
      start_time = Time.current
      status, headers, response = @app.call(env)
      end_time = Time.current

      model_name = extract_model_name(env)

      if trackable_request?(model_name)
        EzlogsRubyAgent::EventQueue.add({
          type: "http_request",
          method: env["REQUEST_METHOD"],
          path: env["PATH_INFO"],
          params: parse_params(env),
          status: status,
          response_time: (end_time - start_time).to_f,
          timestamp: Time.current
        })
      end

      [status, headers, response]
    end

    private

    def extract_model_name(env)
      path_parts = env["PATH_INFO"].split("/")
      path_parts[1].singularize.camelize if path_parts.size > 1
    end

    def parse_params(env)
      Rack::Utils.parse_nested_query(env["rack.input"].read)
    rescue
      {}
    end

    def trackable_request?(model_name)
      return true if model_name.nil?

      config = EzlogsRubyAgent.config
      (config.models_to_track.empty? || config.models_to_track.include?(model_name)) &&
        !config.exclude_models.include?(model_name)
    end
  end
end
