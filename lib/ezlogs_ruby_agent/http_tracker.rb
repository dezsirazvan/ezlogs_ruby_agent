require 'rack'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/time'
# require 'active_support/core_ext/hash/compact' # Removed due to LoadError
require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'
require 'ezlogs_ruby_agent/correlation_manager'

module EzlogsRubyAgent
  class HttpTracker
    def initialize(app)
      @app = app
    end

    def call(env)
      start_time = Time.now

      # Start correlation context for this request
      request_id = extract_request_id(env)
      session_id = extract_session_id(env)
      correlation_context = CorrelationManager.start_request_context(
        request_id,
        session_id,
        extract_request_metadata(env)
      )

      status, headers, response = @app.call(env)
      end_time = Time.now

      # Track the HTTP request event
      track_http_request(env, status, headers, response, start_time, end_time, correlation_context)

      [status, headers, response]
    ensure
      # Clean up correlation context
      CorrelationManager.clear_context
    end

    private

    def track_http_request(env, status, headers, response, start_time, end_time, _correlation_context)
      return unless trackable_request?(env)

      begin
        # Create UniversalEvent with proper schema
        event = UniversalEvent.new(
          event_type: 'http.request',
          action: "#{env['REQUEST_METHOD']} #{extract_path(env)}",
          actor: extract_actor(env),
          subject: extract_subject(env),
          metadata: extract_request_metadata(env, status, headers, response, start_time, end_time),
          timestamp: start_time
        )

        # Log the event
        EzlogsRubyAgent.writer.log(event)
      rescue StandardError => e
        warn "[Ezlogs] Failed to create HTTP event: #{e.message}"
      end
    end

    def extract_request_id(env)
      # Try various sources for request ID
      env['HTTP_X_REQUEST_ID'] ||
        env['HTTP_X_CORRELATION_ID'] ||
        env['HTTP_X_TRACE_ID'] ||
        generate_request_id
    end

    def extract_session_id(env)
      # Extract session ID from various sources
      env['HTTP_X_SESSION_ID'] ||
        extract_session_from_cookie(env) ||
        nil
    end

    def extract_session_from_cookie(env)
      return nil unless env['HTTP_COOKIE']

      cookies = Rack::Utils.parse_cookies(env['HTTP_COOKIE'])
      cookies['_session_id'] || cookies['session_id']
    end

    def extract_path(env)
      path = env['PATH_INFO']
      query = env['QUERY_STRING']

      if query && !query.empty?
        "#{path}?#{query}"
      else
        path
      end
    end

    def extract_actor(env)
      ActorExtractor.extract_actor(env)
    end

    def extract_subject(env)
      path = env['PATH_INFO']

      # Extract resource type and ID from path
      path_parts = path.split('/').reject(&:empty?)
      return nil if path_parts.empty?

      resource_type = path_parts.first.singularize
      resource_id = path_parts[1] if path_parts.size > 1

      # Handle GraphQL requests specially
      return extract_graphql_subject(env) if path.include?('graphql')

      {
        type: resource_type,
        id: resource_id,
        path: path
      }
    end

    def extract_graphql_subject(env)
      body = begin
        env['rack.input'].rewind
        JSON.parse(env['rack.input'].read)
      rescue
        {}
      end

      operation_name = body['operationName'] || 'unknown'
      query_type = extract_graphql_query_type(body['query'])

      {
        type: 'graphql',
        id: operation_name,
        operation: query_type,
        query: body['query']&.truncate(100)
      }
    end

    def extract_graphql_query_type(query)
      return 'unknown' unless query.is_a?(String)

      if query.match?(/\bmutation\b/i)
        'mutation'
      elsif query.match?(/\bsubscription\b/i)
        'subscription'
      else
        'query'
      end
    end

    def extract_request_metadata(env, status = nil, _headers = nil, response = nil, start_time = nil, end_time = nil)
      metadata = {
        method: env['REQUEST_METHOD'],
        path: env['PATH_INFO'],
        query_string: env['QUERY_STRING'],
        user_agent: env['HTTP_USER_AGENT'],
        ip_address: extract_client_ip(env),
        host: env['HTTP_HOST'],
        referer: env['HTTP_REFERER'],
        content_type: env['CONTENT_TYPE'],
        content_length: env['CONTENT_LENGTH']
      }

      # Add timing information if available
      if start_time && end_time
        metadata[:duration] = (end_time - start_time).to_f
        metadata[:start_time] = start_time.iso8601
        metadata[:end_time] = end_time.iso8601
      end

      # Add response information if available
      if status
        metadata[:status] = status
        metadata[:status_category] = status.to_s[0]
      end

      # Add error information for failed requests
      metadata[:error] = extract_error_details(response) if status&.to_s&.start_with?('4', '5')

      # Add request parameters (sanitized)
      metadata[:params] = extract_sanitized_params(env)

      metadata.compact
    end

    def extract_client_ip(env)
      # Try various headers for client IP
      env['HTTP_X_FORWARDED_FOR']&.split(',')&.first&.strip ||
        env['HTTP_X_REAL_IP'] ||
        env['HTTP_X_CLIENT_IP'] ||
        env['REMOTE_ADDR']
    end

    def extract_error_details(response)
      return nil unless response

      if response.is_a?(Array) && response[2].respond_to?(:body)
        begin
          body = response[2].body
          error_data = JSON.parse(body)
          error_data['error'] || error_data['message'] || 'Unknown error'
        rescue JSON::ParserError
          body.to_s.truncate(200)
        end
      elsif response.is_a?(String)
        response.truncate(200)
      else
        'Unknown error'
      end
    end

    def extract_sanitized_params(env)
      return {} unless env['rack.input']

      begin
        env['rack.input'].rewind
        params = Rack::Utils.parse_nested_query(env['rack.input'].read)

        # Sanitize sensitive parameters
        sanitize_params(params)
      rescue
        {}
      end
    end

    def sanitize_params(params)
      params.transform_values do |value|
        if value.is_a?(Hash)
          sanitize_params(value)
        elsif value.is_a?(Array)
          value.map { |v| v.is_a?(Hash) ? sanitize_params(v) : v }
        else
          value
        end
      end
    end

    def generate_request_id
      "req_#{SecureRandom.urlsafe_base64(16).tr('_-', 'ef')}"
    end

    def trackable_request?(env)
      path = env['PATH_INFO']
      return false if path.nil?

      config = EzlogsRubyAgent.config

      # Check if path matches any excluded patterns
      excluded = config.exclude_resources.any? do |pattern|
        path.match?(pattern)
      end
      return false if excluded

      # Check if path matches any included patterns
      if config.resources_to_track.any?
        included = config.resources_to_track.any? do |pattern|
          path.match?(pattern)
        end
        return false unless included
      end

      true
    end
  end
end
