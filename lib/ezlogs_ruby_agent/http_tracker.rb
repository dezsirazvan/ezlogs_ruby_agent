require 'rack'
require 'active_support/all'
require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'

module EzlogsRubyAgent
  class HttpTracker
    def initialize(app)
      @app = app
    end

    def call(env)
      start_time = Time.now
      correlation_id = extract_correlation_id(env)
      resource_id = extract_resource_id(env)

      status, headers, response = @app.call(env)
      end_time = Time.now

      resource_name = extract_resource_name(env)
      error_message = extract_error_message_from_response(response) if status.to_s.start_with?('4', '5')

      if trackable_request?(resource_name)
        begin
          event = UniversalEvent.new(
            event_type: "http_request",
            resource: resource_name,
            resource_id: resource_id,
            action: env["REQUEST_METHOD"],
            actor: extract_actor(env),
            timestamp: start_time,
            metadata: {
              "path" => env["PATH_INFO"],
              "params" => parse_params(env),
              "status" => status,
              "duration" => (end_time - start_time).to_f,
              "user_agent" => env["HTTP_USER_AGENT"],
              "ip_address" => env["REMOTE_ADDR"],
              "error_message" => error_message
            },
            duration: (end_time - start_time).to_f
          )

          EzlogsRubyAgent.writer.log(event.to_h)
        rescue StandardError => e
          warn "[Ezlogs] failed to create HTTP event: #{e.message}"
        end
      end

      [status, headers, response]
    end

    private

    def extract_correlation_id(env)
      env["HTTP_X_CORRELATION_ID"] || Thread.current[:correlation_id] || SecureRandom.uuid
    end

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

    def extract_actor(env)
      ActorExtractor.extract_actor(env)
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
  end
end
