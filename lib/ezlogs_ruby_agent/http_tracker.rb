require 'rack'
require 'active_support/all'
require 'ezlogs_ruby_agent/event_queue'
require 'ezlogs_ruby_agent/actor_extractor'

module EzlogsRubyAgent
  class HttpTracker
    def initialize(app)
      @app = app
    end

    def call(env)
      start_time = Time.current
      correlation_id = env["HTTP_X_CORRELATION_ID"] || SecureRandom.uuid
      resource_id = extract_resource_id(env)

      status, headers, response = @app.call(env)
      end_time = Time.current

      model_name = extract_model_name(env)

      error_message = nil
      if status.to_s.start_with?('4') || status.to_s.start_with?('5')
        error_message = extract_error_message_from_response(response)
      end

      actor = ActorExtractor.extract_actor(env)

      if trackable_request?(model_name)
        add_event({
          type: "http_request",
          method: env["REQUEST_METHOD"],
          path: env["PATH_INFO"],
          params: parse_params(env),
          status: status,
          duration: (end_time - start_time).to_f,
          correlation_id: correlation_id,
          resource_id: resource_id,
          error_message: error_message,
          user_agent: env["HTTP_USER_AGENT"],
          actor: actor,
          ip_address: env["REMOTE_ADDR"],
          timestamp: Time.current
        })
      end

      [status, headers, response]
    end

    private

    def extract_resource_id(env)
      if env["PATH_INFO"].include?("graphql")
        extract_resource_id_from_graphql(env)
      else
        path_parts = env["PATH_INFO"].split("/")
        path_parts[1].singularize.camelize if path_parts.size > 1
      end
    end

    def extract_resource_id_from_graphql(env)
      body = begin
        JSON.parse(env["rack.input"].read)
      rescue
        {}
      end
      variables = body["variables"] || {}

      variables["id"]
    end

    def extract_error_message_from_response(response)
      response_body = response.body
      begin
        error_details = JSON.parse(response_body)
        error_message = error_details["error"] || error_details["message"] || "Unknown error"
      rescue JSON::ParserError
        error_message = response_body
      end
      error_message
    end

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

    def add_event(event_data)
      EzlogsRubyAgent::EventQueue.instance.add(event_data)
    end
  end
end
