require 'rack'
require 'active_support/all'
require 'ezlogs_ruby_agent/event_queue'

module EzlogsRubyAgent
  class HttpTracker
    def initialize(app)
      @app = app
    end

    def call(env)
      start_time = Time.current
      resource_id = extract_resource_id(env)

      status, headers, response = @app.call(env)
      end_time = Time.current

      resource_name = extract_resource_name(env)

      error_message = nil
      if status.to_s.start_with?('4') || status.to_s.start_with?('5')
        error_message = extract_error_message_from_response(response)
      end

      if trackable_request?(resource_name)
        add_event({
          type: "http_request",
          method: env["REQUEST_METHOD"],
          path: env["PATH_INFO"],
          params: parse_params(env),
          status: status,
          duration: (end_time - start_time).to_f,
          resource_id: resource_id,
          error_message: error_message,
          user_agent: env["HTTP_USER_AGENT"],
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
      return response if response.is_a?(String) || response.is_a?(Array)

      begin
        response_body = response.body

        error_details = JSON.parse(response_body)
        error_message = error_details["error"] || error_details["message"] || "Unknown error"
      rescue JSON::ParserError
        error_message = response
      end
      error_message
    end

    def extract_resource_name(env)
      path_parts = env["PATH_INFO"].split("/")
      path_parts[1].singularize if path_parts.size > 1
    end

    def parse_params(env)
      Rack::Utils.parse_nested_query(env["rack.input"].read)
    rescue
      {}
    end

    def trackable_request?(resource_name)
      return true if resource_name.nil?

      config = EzlogsRubyAgent.config
      (
        config.resources_to_track.empty? || 
        config.resources_to_track.map(&:downcase).include?(resource_name.downcase)
      ) &&
        !config.exclude_resources.map(&:downcase).include?(resource_name.downcase)
    end

    def add_event(event_data)
    end
  end
end
