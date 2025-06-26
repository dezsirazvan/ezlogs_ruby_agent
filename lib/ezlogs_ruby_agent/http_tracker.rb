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
      correlation_context = EzlogsRubyAgent::CorrelationManager.start_request_context(request_id, session_id)

      # Call the app
      status, headers, response = @app.call(env)
      end_time = Time.now

      # Track the HTTP request
      track_http_request(env, status, headers, response, start_time, end_time, correlation_context)

      [status, headers, response]
    rescue StandardError => e
      end_time = Time.now
      track_http_request(env, 500, { 'Content-Type' => 'application/json' }, e, start_time, end_time,
                         correlation_context)
      raise
    end

    private

    def track_http_request(env, status, headers, response, start_time, end_time, correlation_context)
      return unless trackable_request?(env)

      begin
        # Create UniversalEvent with proper schema
        event = UniversalEvent.new(
          event_type: 'http.request',
          action: "#{env['REQUEST_METHOD']} #{extract_path(env)}",
          actor: extract_actor(env),
          subject: extract_subject(env),
          metadata: extract_request_metadata(env, status, headers, response, start_time, end_time),
          timestamp: start_time,
          correlation_id: correlation_context&.correlation_id
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
        query: truncate_string(body['query'], 100)
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
          truncate_string(body.to_s, 200)
        end
      elsif response.is_a?(String)
        truncate_string(response, 200)
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
      return {} unless params.is_a?(Hash)

      # Apply the same sanitization logic as EventProcessor
      sanitized_fields = []

      # Get sensitive field patterns from configuration
      config = EzlogsRubyAgent.config
      all_sensitive_fields = %w[password passwd pwd secret token api_key access_key credit_card cc_number card_number
                                ssn social_security auth_token session_id cookie] +
                             (config.sanitize_fields || [])

      # Apply field-based sanitization
      sanitize_hash_recursive!(params, all_sensitive_fields, sanitized_fields)

      # Apply pattern-based PII detection if enabled
      detect_pii_recursive!(params, sanitized_fields) if config.auto_detect_pii

      params
    end

    def sanitize_hash_recursive!(hash, sensitive_fields, sanitized_fields, path = '')
      hash.each do |key, value|
        current_path = path.empty? ? key.to_s : "#{path}.#{key}"

        if sensitive_fields.any? { |field| key.to_s.downcase.include?(field.downcase) }
          hash[key] = '[REDACTED]'
          sanitized_fields << current_path
        elsif value.is_a?(Hash)
          sanitize_hash_recursive!(value, sensitive_fields, sanitized_fields, current_path)
        elsif value.is_a?(Array)
          value.each_with_index do |item, index|
            if item.is_a?(Hash)
              sanitize_hash_recursive!(item, sensitive_fields, sanitized_fields, "#{current_path}[#{index}]")
            end
          end
        end
      end
    end

    def detect_pii_recursive!(hash, sanitized_fields, path = '')
      # Default PII patterns
      pii_patterns = {
        'credit_card' => /\b(?:\d{4}[-\s]?){3}\d{4}\b/,
        'ssn' => /\b\d{3}-?\d{2}-?\d{4}\b/,
        'phone' => /\b\(?(\d{3})\)?[-.\s]?(\d{3})[-.\s]?(\d{4})\b/,
        'email_loose' => /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/
      }

      # Add custom patterns from config
      config = EzlogsRubyAgent.config
      pii_patterns.merge!(config.custom_patterns || {})

      hash.each do |key, value|
        current_path = path.empty? ? key.to_s : "#{path}.#{key}"

        case value
        when String
          pii_patterns.each_value do |pattern|
            next unless value.match?(pattern)

            hash[key] = '[REDACTED]'
            sanitized_fields << current_path
            break
          end
        when Hash
          detect_pii_recursive!(value, sanitized_fields, current_path)
        when Array
          value.each_with_index do |item, index|
            if item.is_a?(Hash)
              detect_pii_recursive!(item, sanitized_fields, "#{current_path}[#{index}]")
            elsif item.is_a?(String)
              pii_patterns.each_value do |pattern|
                next unless item.match?(pattern)

                value[index] = '[REDACTED]'
                sanitized_fields << "#{current_path}[#{index}]"
                break
              end
            end
          end
        end
      end
    end

    def generate_request_id
      "req_#{SecureRandom.urlsafe_base64(16).tr('_-', 'ef')}"
    end

    def truncate_string(str, length)
      return nil if str.nil?
      return str if str.length <= length

      "#{str[0..length - 4]}..."
    end

    def trackable_request?(env)
      path = env['PATH_INFO']
      return false if path.nil?

      config = EzlogsRubyAgent.config

      # Check if path matches any excluded patterns
      excluded = config.excluded_resources.any? do |pattern|
        path.match?(pattern)
      end
      return false if excluded

      # Check if path matches any included patterns
      if config.included_resources.any?
        included = config.included_resources.any? do |pattern|
          path.match?(pattern)
        end
        return false unless included
      end

      true
    end
  end
end
