require 'rack'
require 'json'
require 'set'
require 'base64'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/time'
require 'active_support/core_ext/hash/deep_merge'
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

      # Populate thread-local context for other components
      populate_thread_context(env, status, headers, start_time, end_time)

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
      ensure
        # Clear thread-local context after request
        clear_thread_context
      end
    end

    def populate_thread_context(env, status, headers, start_time, end_time)
      # Store request information for other components to access
      Thread.current[:current_request_ip] = extract_client_ip(env)
      Thread.current[:current_user_agent] = env['HTTP_USER_AGENT']
      Thread.current[:current_controller] = env['action_controller.instance']

      # Store timing information for database/job tracking
      if start_time && end_time
        Thread.current[:ezlogs_request_start] = start_time
        Thread.current[:ezlogs_request_end] = end_time
      end

      # Store user identification
      user_id = extract_user_id(env)
      Thread.current[:current_user_id] = user_id if user_id

      # Store session information
      session_id = extract_session_id(env)
      Thread.current[:current_session_id] = session_id if session_id
    end

    def clear_thread_context
      # Clean up thread-local variables
      Thread.current[:current_request_ip] = nil
      Thread.current[:current_user_agent] = nil
      Thread.current[:current_controller] = nil
      Thread.current[:current_user_id] = nil
      Thread.current[:current_session_id] = nil
      Thread.current[:ezlogs_request_start] = nil
      Thread.current[:ezlogs_request_end] = nil
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

    def extract_request_metadata(env, status = nil, headers = nil, response = nil, start_time = nil, end_time = nil)
      metadata = {
        request: build_request_details(env),
        params: extract_comprehensive_params(env),
        timing: build_timing_breakdown(env, start_time, end_time),
        response: build_response_details(status, headers, response),
        headers: extract_important_headers(env),
        context: build_request_context(env),
        database: extract_database_activity,
        performance: extract_performance_metrics
      }

      metadata.compact
    end

    def build_request_details(env)
      {
        method: env['REQUEST_METHOD'],
        path: env['PATH_INFO'],
        full_path: build_full_path(env),
        controller: extract_controller_info(env),
        action: extract_action_info(env),
        format: extract_format(env),
        protocol: env['SERVER_PROTOCOL'] || 'HTTP/1.1',
        host: env['HTTP_HOST'],
        port: env['SERVER_PORT']
      }.compact
    end

    def extract_comprehensive_params(env)
      # Extract both query and body parameters
      query_params = extract_query_params(env)
      body_params = extract_body_params(env)

      # Merge and sanitize
      all_params = merge_params(query_params, body_params)

      {
        filtered: sanitize_params_deeply(all_params),
        summary: build_params_summary(all_params),
        raw_sizes: {
          query_string_bytes: env['QUERY_STRING']&.bytesize || 0,
          body_bytes: extract_body_size(env),
          total_bytes: (env['QUERY_STRING']&.bytesize || 0) + extract_body_size(env)
        }
      }
    end

    def build_timing_breakdown(env, start_time, end_time)
      return {} unless start_time && end_time

      total_duration_ms = ((end_time - start_time) * 1000).round(3)

      timing = {
        started_at: start_time.iso8601(3),
        completed_at: end_time.iso8601(3),
        total_duration_ms: total_duration_ms,
        view_duration_ms: extract_view_duration,
        db_duration_ms: extract_db_duration,
        allocations: extract_allocations_count,
        gc_runs: extract_gc_runs
      }

      # Add detailed timing if available
      timing.merge!(extract_rails_timing_details) if defined?(Rails) && Rails.logger.respond_to?(:formatter)

      timing.compact
    end

    def build_response_details(status, headers, response)
      return {} unless status

      response_details = {
        status: status,
        status_category: categorize_status(status),
        content_type: headers&.dig('Content-Type'),
        content_length: calculate_response_size(response),
        cache_status: extract_cache_status(headers),
        redirect_location: headers&.dig('Location')
      }

      # Add error details for non-2xx responses
      if status >= 400
        response_details[:error] = extract_error_details(response)
        response_details[:error_class] = extract_error_class(response)
      end

      response_details.compact
    end

    def extract_important_headers(env)
      important_header_patterns = %w[
        HTTP_CONTENT_TYPE
        HTTP_CONTENT_LENGTH
        HTTP_ACCEPT
        HTTP_REFERER
        HTTP_X_REQUESTED_WITH
        HTTP_ACCEPT_LANGUAGE
        HTTP_ACCEPT_ENCODING
        HTTP_CONNECTION
        HTTP_UPGRADE_INSECURE_REQUESTS
      ]

      headers = {}
      important_header_patterns.each do |pattern|
        next unless env[pattern]

        # Convert HTTP_CONTENT_TYPE to content_type
        key = pattern.sub('HTTP_', '').downcase
        headers[key] = env[pattern]
      end

      # Add authorization header info (without exposing the actual token)
      if env['HTTP_AUTHORIZATION']
        auth_type = env['HTTP_AUTHORIZATION'].split(' ').first
        headers['authorization_type'] = auth_type
        headers['has_authorization'] = true
      end

      headers
    end

    def build_request_context(env)
      current_context = EzlogsRubyAgent::CorrelationManager.current_context

      context = {
        user_id: extract_user_id(env),
        session_id: extract_session_id(env),
        request_id: extract_request_id(env),
        ip_address: extract_client_ip(env),
        user_agent: env['HTTP_USER_AGENT'],
        environment: Rails.env || ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'unknown',
        app_version: extract_app_version,
        gem_version: EzlogsRubyAgent::VERSION
      }

      # Add correlation info if available
      if current_context
        context[:correlation_id] = current_context.correlation_id
        context[:flow_id] = current_context.flow_id
      end

      context.compact
    end

    def extract_database_activity
      # Try to capture database metrics during request
      db_metrics = {}

      # Check for ActiveRecord query log
      db_metrics = extract_activerecord_metrics if defined?(ActiveRecord) && ActiveRecord::Base.logger

      # Check thread-local database stats
      if Thread.current[:ezlogs_db_stats]
        db_metrics.merge!(Thread.current[:ezlogs_db_stats])
        Thread.current[:ezlogs_db_stats] = nil # Clear after use
      end

      db_metrics
    end

    def extract_performance_metrics
      performance = {}

      # Memory usage
      begin
        if RUBY_PLATFORM.include?('linux')
          memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
          performance[:memory_usage_mb] = memory_mb.round(2)
        end
      rescue StandardError
        # Ignore memory extraction errors
      end

      # GC stats
      if defined?(GC) && GC.respond_to?(:stat)
        gc_stats = GC.stat
        performance[:gc_stats] = {
          total_allocations: gc_stats[:total_allocated_objects],
          heap_live_slots: gc_stats[:heap_live_slots],
          heap_free_slots: gc_stats[:heap_free_slots],
          major_gc_count: gc_stats[:major_gc_count],
          minor_gc_count: gc_stats[:minor_gc_count]
        }
      end

      performance
    end

    # Helper methods for the new functionality

    def build_full_path(env)
      path = env['PATH_INFO'] || '/'
      query = env['QUERY_STRING']

      if query && !query.empty?
        "#{path}?#{query}"
      else
        path
      end
    end

    def extract_controller_info(env)
      # Try to extract from Rails route info
      if env['action_controller.instance']
        controller = env['action_controller.instance']
        return controller.class.name
      end

      # Try to extract from path
      path = env['PATH_INFO']
      if path && path.include?('/')
        parts = path.split('/').reject(&:empty?)
        return parts.first&.singularize&.classify if parts.any?
      end

      nil
    end

    def extract_action_info(env)
      # Try to extract from Rails route info
      if env['action_controller.instance']
        controller = env['action_controller.instance']
        return controller.action_name
      end

      # Try to infer from HTTP method and path
      method = env['REQUEST_METHOD']&.downcase
      path = env['PATH_INFO']

      return 'show' if method == 'get' && path&.match?(%r{/\d+$})
      return 'index' if method == 'get'
      return 'create' if method == 'post'
      return 'update' if %w[put patch].include?(method)
      return 'destroy' if method == 'delete'

      'unknown'
    end

    def extract_format(env)
      # Try to extract from Accept header
      accept = env['HTTP_ACCEPT']
      return 'json' if accept&.include?('application/json')
      return 'xml' if accept&.include?('application/xml')
      return 'html' if accept&.include?('text/html')

      # Try to extract from path extension
      path = env['PATH_INFO']
      if path&.include?('.')
        extension = File.extname(path)[1..-1]
        return extension if %w[json xml html txt csv].include?(extension)
      end

      'html' # default
    end

    def extract_query_params(env)
      query_string = env['QUERY_STRING']
      return {} unless query_string && !query_string.empty?

      begin
        Rack::Utils.parse_nested_query(query_string)
      rescue StandardError
        {}
      end
    end

    def extract_body_params(env)
      return {} unless env['rack.input']

      begin
        env['rack.input'].rewind
        body_content = env['rack.input'].read
        env['rack.input'].rewind # Reset for other middlewares

        return {} if body_content.empty?

        content_type = env['CONTENT_TYPE']

        if content_type&.include?('application/json')
          JSON.parse(body_content)
        elsif content_type&.include?('application/x-www-form-urlencoded')
          Rack::Utils.parse_nested_query(body_content)
        elsif content_type&.include?('multipart/form-data')
          parse_multipart_data(body_content, content_type)
        else
          # Store raw body for other content types
          { '_raw_body' => body_content[0..1000] } # Limit raw body size
        end
      rescue StandardError => e
        { '_parse_error' => e.message }
      end
    end

    def merge_params(query_params, body_params)
      # Deep merge query and body params
      query_params.deep_merge(body_params)
    rescue StandardError
      query_params.merge(body_params)
    end

    def build_params_summary(params)
      {
        param_count: count_params_recursive(params),
        has_file_uploads: has_file_uploads?(params),
        has_nested_params: has_nested_params?(params),
        total_size_bytes: calculate_params_size(params),
        content_types: extract_param_content_types(params)
      }
    end

    def sanitize_params_deeply(params)
      return {} unless params.is_a?(Hash)

      # Use existing sanitization logic but apply it deeply
      sanitized_fields = []
      config = EzlogsRubyAgent.config

      # Get sensitive field patterns
      all_sensitive_fields = %w[password passwd pwd secret token api_key access_key credit_card cc_number card_number
                                ssn social_security auth_token session_id cookie] +
                             (config.security&.sensitive_fields || [])

      sanitized_params = deep_dup(params)
      sanitize_hash_recursive!(sanitized_params, all_sensitive_fields, sanitized_fields)

      # Apply PII detection if enabled
      detect_pii_recursive!(sanitized_params, sanitized_fields) if config.security&.auto_detect_pii

      sanitized_params
    end

    def extract_body_size(env)
      content_length = env['CONTENT_LENGTH']
      return content_length.to_i if content_length

      # Try to calculate from rack.input if available
      if env['rack.input']
        begin
          current_pos = env['rack.input'].pos
          env['rack.input'].seek(0, IO::SEEK_END)
          size = env['rack.input'].pos
          env['rack.input'].seek(current_pos)
          return size
        rescue StandardError
          # Ignore if we can't determine size
        end
      end

      0
    end

    def categorize_status(status)
      case status
      when 200..299
        'success'
      when 300..399
        'redirect'
      when 400..499
        'client_error'
      when 500..599
        'server_error'
      else
        'unknown'
      end
    end

    def extract_cache_status(headers)
      return 'hit' if headers&.dig('X-Cache')&.include?('HIT')
      return 'miss' if headers&.dig('X-Cache')&.include?('MISS')
      return 'bypass' if headers&.dig('X-Cache')&.include?('BYPASS')

      # Check for standard cache control headers
      cache_control = headers&.dig('Cache-Control')
      return 'no-cache' if cache_control&.include?('no-cache')
      return 'private' if cache_control&.include?('private')

      nil
    end

    def calculate_response_size(response)
      return nil unless response

      if response.is_a?(Array) && response[2]
        body = response[2]
        if body.respond_to?(:to_ary)
          body.to_ary.sum(&:bytesize)
        elsif body.respond_to?(:each)
          size = 0
          body.each { |chunk| size += chunk.bytesize }
          size
        else
          body.to_s.bytesize
        end
      else
        response.to_s.bytesize
      end
    rescue StandardError
      nil
    end

    def extract_error_class(response)
      # Try to extract error class from response if it's an exception
      if response.is_a?(Exception)
        response.class.name
      elsif response.is_a?(Array) && response[2].respond_to?(:body)
        # Try to parse error from JSON response
        begin
          body = response[2].body
          error_data = JSON.parse(body)
          error_data['exception'] || error_data['error_class']
        rescue JSON::ParserError
          nil
        end
      else
        nil
      end
    end

    # Additional helper methods for deep parameter processing

    def count_params_recursive(obj, count = 0)
      case obj
      when Hash
        count += obj.size
        obj.values.each { |v| count = count_params_recursive(v, count) }
      when Array
        obj.each { |v| count = count_params_recursive(v, count) }
      end
      count
    end

    def has_file_uploads?(params)
      return false unless params.is_a?(Hash)

      params.any? do |_key, value|
        case value
        when Hash
          has_file_uploads?(value)
        when Array
          value.any? { |v| has_file_uploads?(v) if v.is_a?(Hash) }
        else
          value.respond_to?(:tempfile) || value.respond_to?(:original_filename)
        end
      end
    end

    def has_nested_params?(params)
      return false unless params.is_a?(Hash)

      params.any? { |_key, value| value.is_a?(Hash) || value.is_a?(Array) }
    end

    def calculate_params_size(params)
      JSON.generate(params).bytesize
    rescue StandardError
      params.to_s.bytesize
    end

    def extract_param_content_types(params)
      types = Set.new

      examine_param_types = lambda do |obj|
        case obj
        when Hash
          types << 'hash'
          obj.values.each(&examine_param_types)
        when Array
          types << 'array'
          obj.each(&examine_param_types)
        when String
          types << 'string'
        when Integer
          types << 'integer'
        when Float
          types << 'float'
        when TrueClass, FalseClass
          types << 'boolean'
        else
          types << 'other'
        end
      end

      examine_param_types.call(params)
      types.to_a
    end

    def deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
      when Array
        obj.map { |v| deep_dup(v) }
      else
        obj.respond_to?(:dup) ? obj.dup : obj
      end
    end

    def parse_multipart_data(body_content, content_type)
      # Basic multipart parsing - in production, you'd want a more robust parser
      boundary = content_type.match(/boundary=([^;]+)/i)&.[](1)
      return { '_multipart_data' => 'present' } unless boundary

      parts = body_content.split("--#{boundary}")
      parsed = {}

      parts.each_with_index do |part, index|
        next if index == 0 || part.strip.empty? || part.strip == '--'

        next unless part.include?("\r\n\r\n")

        headers, content = part.split("\r\n\r\n", 2)

        # Extract field name from Content-Disposition header
        if headers.match(/name="([^"]+)"/i)
          field_name = ::Regexp.last_match(1)
          parsed[field_name] = content.respond_to?(:tempfile) ? '[FILE_UPLOAD]' : content.strip
        end
      end

      parsed
    rescue StandardError
      { '_multipart_error' => 'Failed to parse multipart data' }
    end

    # Performance extraction helpers

    def extract_view_duration
      # Try to get from Rails instrumentation
      if Thread.current[:ezlogs_view_duration]
        duration = Thread.current[:ezlogs_view_duration]
        Thread.current[:ezlogs_view_duration] = nil
        return duration.round(3)
      end

      nil
    end

    def extract_db_duration
      # Try to get from Rails instrumentation
      if Thread.current[:ezlogs_db_duration]
        duration = Thread.current[:ezlogs_db_duration]
        Thread.current[:ezlogs_db_duration] = nil
        return duration.round(3)
      end

      nil
    end

    def extract_allocations_count
      if Thread.current[:ezlogs_allocations]
        allocations = Thread.current[:ezlogs_allocations]
        Thread.current[:ezlogs_allocations] = nil
        return allocations
      end

      nil
    end

    def extract_gc_runs
      if Thread.current[:ezlogs_gc_runs]
        gc_runs = Thread.current[:ezlogs_gc_runs]
        Thread.current[:ezlogs_gc_runs] = nil
        return gc_runs
      end

      nil
    end

    def extract_rails_timing_details
      details = {}

      # Check for Rails request timing information
      if Thread.current[:ezlogs_rails_timing]
        timing_data = Thread.current[:ezlogs_rails_timing]
        details.merge!(timing_data)
        Thread.current[:ezlogs_rails_timing] = nil
      end

      details
    end

    def extract_activerecord_metrics
      metrics = {}

      # Try to get query count and timing from ActiveRecord
      if defined?(ActiveRecord) && ActiveRecord::Base.connection_pool
        begin
          # This is a simplified version - in practice you'd hook into ActiveRecord's instrumentation
          metrics[:query_count] = Thread.current[:ezlogs_query_count] || 0
          metrics[:total_query_time_ms] = Thread.current[:ezlogs_total_query_time] || 0

          # Clear thread-local variables
          Thread.current[:ezlogs_query_count] = nil
          Thread.current[:ezlogs_total_query_time] = nil
        rescue StandardError
          # Ignore ActiveRecord errors
        end
      end

      metrics
    end

    def extract_user_id(env)
      # Try multiple methods to extract user ID

      # Check for Warden (Devise)
      return env['warden'].user.id.to_s if env['warden']&.user

      # Check for session user_id
      return env['rack.session']['user_id'].to_s if env['rack.session'] && env['rack.session']['user_id']

      # Check for current_user in thread (set by controller)
      return Thread.current[:current_user].id.to_s if Thread.current[:current_user]

      # Check for JWT token
      if env['HTTP_AUTHORIZATION']
        user_id = extract_user_from_jwt(env['HTTP_AUTHORIZATION'])
        return user_id if user_id
      end

      nil
    end

    def extract_user_from_jwt(auth_header)
      # Basic JWT user extraction - implement based on your JWT structure
      return nil unless auth_header.start_with?('Bearer ')

      token = auth_header[7..-1]

      begin
        # This is a simplified version - implement proper JWT decoding
        payload = JSON.parse(Base64.decode64(token.split('.')[1]))
        payload['user_id'] || payload['sub']
      rescue StandardError
        nil
      end
    end

    def extract_app_version
      # Try multiple ways to get app version
      return Rails.application.config.version if defined?(Rails) && Rails.application&.config&.respond_to?(:version)
      return ENV['APP_VERSION'] if ENV['APP_VERSION']

      # Try to read from VERSION file
      version_file = File.join(Dir.pwd, 'VERSION')
      return File.read(version_file).strip if File.exist?(version_file)

      'unknown'
    rescue StandardError
      'unknown'
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
