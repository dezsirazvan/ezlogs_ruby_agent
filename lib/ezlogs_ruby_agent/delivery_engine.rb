require 'net/http'
require 'net/https'
require 'zlib'
require 'json'
require 'timeout'
require 'ostruct'

module EzlogsRubyAgent
  # Delivery result with detailed information
  class DeliveryResult
    attr_reader :success, :status_code, :error, :retry_count, :response_time,
                :delivered_count, :failed_count, :compressed

    def initialize(success:, status_code: nil, error: nil, retry_count: 0,
                   response_time: 0.0, delivered_count: 0, failed_count: 0, compressed: false)
      @success = success
      @status_code = status_code
      @error = error
      @retry_count = retry_count
      @response_time = response_time
      @delivered_count = delivered_count
      @failed_count = failed_count
      @compressed = compressed
    end

    def success?
      @success
    end

    def failure?
      !@success
    end
  end

  # Circuit breaker for handling service failures
  class CircuitBreaker
    attr_reader :state, :failure_count, :last_failure_time

    def initialize(threshold, timeout)
      @threshold = threshold
      @timeout = timeout
      @state = :closed
      @failure_count = 0
      @last_failure_time = nil
      @mutex = Mutex.new
    end

    def call
      @mutex.synchronize do
        if open?
          # Only allow attempt if timeout has expired
          raise 'circuit breaker open' unless should_attempt_reset?

          @state = :half_open
        end
      end

      begin
        result = yield
        @mutex.synchronize do
          if half_open?
            @state = :closed
            @failure_count = 0
            @last_failure_time = nil
          elsif closed?
            @failure_count = 0
            @last_failure_time = nil
          end
        end
        result
      rescue StandardError => e
        @mutex.synchronize do
          if half_open?
            @state = :open
            @last_failure_time = Time.now
            @failure_count = @threshold
            # After a failed half-open attempt, immediately raise
            raise 'circuit breaker open'
          else
            @failure_count += 1
            @last_failure_time = Time.now
            @state = :open if @failure_count >= @threshold
            # If breaker just opened, immediately raise on this call
            raise 'circuit breaker open' if @state == :open
          end
        end
        raise e
      end
    end

    def closed?
      @state == :closed
    end

    def open?
      @state == :open
    end

    def half_open?
      @state == :half_open
    end

    private

    def should_attempt_reset?
      return false unless open?
      return false unless @last_failure_time

      Time.now - @last_failure_time >= @timeout
    end
  end

  # Connection pool for efficient HTTP connections
  class ConnectionPool
    attr_reader :closed

    def initialize(max_connections, endpoint, timeout)
      @max_connections = max_connections
      @endpoint = endpoint
      @timeout = timeout
      @connections = Queue.new
      @closed = false
      @mutex = Mutex.new
    end

    def closed?
      @closed
    end

    def with_connection
      connection = checkout_connection
      begin
        yield connection
      ensure
        checkin_connection(connection) unless @closed
      end
    end

    def shutdown
      @mutex.synchronize do
        @closed = true
        until @connections.empty?
          begin
            conn = @connections.pop(true)
            conn.finish if conn.started?
          rescue ThreadError
            break
          end
        end
      end
    end

    private

    def checkout_connection
      return create_connection if @connections.empty?

      begin
        @connections.pop(true)
      rescue ThreadError
        create_connection
      end
    end

    def checkin_connection(connection)
      return if @closed || !connection.started?

      begin
        @connections.push(connection) if @connections.size < @max_connections
      rescue ThreadError
        # Pool is full, close the connection
        connection.finish
      end
    end

    def create_connection
      uri = URI.parse(@endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http
    end
  end

  # Production-grade delivery engine with connection pooling, circuit breaker,
  # retry logic, compression, and comprehensive monitoring
  class DeliveryEngine
    # Retryable HTTP status codes
    RETRYABLE_STATUSES = [408, 429, 500, 502, 503, 504].freeze

    # Initialize the delivery engine
    #
    # @param config [Configuration] Configuration object
    def initialize(config)
      @config = config
      @circuit_breaker = CircuitBreaker.new(
        @config.delivery.circuit_breaker_threshold,
        @config.delivery.circuit_breaker_timeout
      )
      @connection_pool = ConnectionPool.new(
        @config.performance.connection_pool_size,
        @config.delivery.endpoint,
        @config.delivery.timeout
      )
      @metrics = {
        total_requests: 0,
        successful_requests: 0,
        failed_requests: 0,
        total_response_time: 0.0,
        total_retries: 0
      }
      @metrics_mutex = Mutex.new
    end

    # Deliver a single event
    #
    # @param event_data [Hash] Event data to deliver
    # @return [DeliveryResult] Delivery result with details
    def deliver(event_data)
      return DeliveryResult.new(success: false, error: 'No endpoint configured') unless @config.delivery.endpoint

      start_time = Time.now
      last_status_code = nil
      last_error = nil
      result_retry_count = 0

      begin
        # Use circuit breaker to wrap the entire delivery attempt
        result = @circuit_breaker.call do
          # If circuit breaker has any failure count, don't retry to ensure proper tracking
          if @circuit_breaker.failure_count.positive?
            delivery_result = perform_delivery(event_data, 0)
            if delivery_result.success?
              record_metrics(true, Time.now - start_time, 0)
              return delivery_result
            else
              last_status_code = delivery_result.status_code
              last_error = delivery_result.error
              result_retry_count = 0
              raise "HTTP #{delivery_result.status_code}: #{delivery_result.error}"
            end
          end

          # Retry loop for HTTP status errors (only when no recent failures)
          inner_retry_count = 0
          loop do
            delivery_result = perform_delivery(event_data, inner_retry_count)
            if delivery_result.success?
              record_metrics(true, Time.now - start_time, inner_retry_count)
              return delivery_result
            end

            # Don't retry on 500 errors if circuit breaker has any failures
            if delivery_result.status_code == 500 && @circuit_breaker.failure_count.positive?
              last_status_code = delivery_result.status_code
              last_error = delivery_result.error
              result_retry_count = inner_retry_count
              raise "HTTP #{delivery_result.status_code}: #{delivery_result.error}"
            end

            # If it's a retryable error, retry up to the limit
            if retryable_error?(delivery_result.status_code) && inner_retry_count < @config.delivery.retry_attempts
              inner_retry_count += 1
              sleep(@config.delivery.retry_backoff**inner_retry_count)
              next
            end

            # Non-retryable error or max retries reached - raise to circuit breaker
            last_status_code = delivery_result.status_code
            last_error = delivery_result.error
            result_retry_count = inner_retry_count
            raise "HTTP #{delivery_result.status_code}: #{delivery_result.error}"
          rescue StandardError => e
            # If circuit breaker open, re-raise immediately
            raise e if e.message == 'circuit breaker open'

            inner_retry_count += 1
            last_status_code = extract_status_code(e.message)
            last_error = e.message
            result_retry_count = inner_retry_count - 1
            if inner_retry_count > @config.delivery.retry_attempts
              # Always raise so circuit breaker can track failures
              raise e
            end
            # Only retry on network/connection errors (timeout, connection refused, etc.)
            # Don't retry on HTTP status errors
            unless e.message.include?('timeout') || e.message.include?('network error') || e.message.include?('connection')
              raise e
            end

            sleep(@config.delivery.retry_backoff**inner_retry_count)
          end
        end
        record_metrics(result.success?, Time.now - start_time, result.retry_count)
        result
      rescue StandardError => e
        # If breaker is open or half-open and fails, always return 'circuit breaker open'
        if e.message == 'circuit breaker open'
          record_metrics(false, Time.now - start_time, result_retry_count)
          return DeliveryResult.new(
            success: false,
            error: 'circuit breaker open',
            retry_count: result_retry_count,
            response_time: Time.now - start_time
          )
        end
        error_message = "Circuit breaker: #{e.message}"
        record_metrics(false, Time.now - start_time, result_retry_count)
        DeliveryResult.new(
          success: false,
          status_code: last_status_code,
          error: error_message,
          retry_count: result_retry_count,
          response_time: Time.now - start_time
        )
      end
    end

    # Deliver a batch of events
    #
    # @param events [Array<Hash>] Array of event data
    # @return [DeliveryResult] Batch delivery result
    def deliver_batch(events)
      return DeliveryResult.new(success: false, error: 'No endpoint configured') unless @config.delivery.endpoint
      return DeliveryResult.new(success: false, error: 'No events to deliver') if events.empty?

      start_time = Time.now
      payload = prepare_batch_payload(events)

      begin
        @circuit_breaker.call do
          result = perform_batch_delivery(payload, events.size)
          record_metrics(result.success?, Time.now - start_time, 0)
          result
        end
      rescue StandardError => e
        record_metrics(false, Time.now - start_time, 0)
        error_message = if e.message.include?('Circuit breaker open')
                          e.message
                        elsif e.message.include?('Circuit breaker:')
                          e.message
                        else
                          "Circuit breaker: #{e.message}"
                        end
        DeliveryResult.new(
          success: false,
          error: error_message,
          response_time: Time.now - start_time
        )
      end
    end

    # Check if the Go agent is healthy and ready to receive events
    #
    # @return [Hash] Health check result with status and details
    def agent_health_check
      return { healthy: false, error: 'No endpoint configured' } unless @config.delivery.endpoint
      return { healthy: true, message: 'Health check disabled' } unless @config.delivery.agent_health_check

      health_endpoint = @config.delivery.agent_health_endpoint
      health_url = URI.join(@config.delivery.endpoint, health_endpoint).to_s

      begin
        @connection_pool.with_connection do |http|
          uri = URI.parse(health_url)
          path = uri.path.empty? ? '/' : uri.path
          request = Net::HTTP::Get.new(path)
          request['User-Agent'] = "EzlogsRubyAgent/#{EzlogsRubyAgent::VERSION}"

          response = http.request(request)

          if response.code.to_i == 200
            { healthy: true, status_code: response.code.to_i, response_time: Time.now }
          else
            { healthy: false, status_code: response.code.to_i, error: response.body }
          end
        end
      rescue Timeout::Error => e
        { healthy: false, error: "Health check timeout: #{e.message}" }
      rescue StandardError => e
        { healthy: false, error: "Health check failed: #{e.message}" }
      end
    end

    # Get health status of the delivery engine
    #
    # @return [Hash] Health status information
    def health_status
      {
        circuit_breaker_state: @circuit_breaker.state.to_s,
        connection_pool_size: @connection_pool.instance_variable_get(:@connections).size,
        total_requests: @metrics[:total_requests],
        successful_requests: @metrics[:successful_requests],
        failed_requests: @metrics[:failed_requests],
        average_response_time: if (@metrics[:total_requests]).positive?
                                 @metrics[:total_response_time] / @metrics[:total_requests]
                               else
                                 0.0
                               end
      }
    end

    # Get delivery metrics
    #
    # @return [Hash] Metrics information
    def metrics
      @metrics_mutex.synchronize do
        metrics_copy = @metrics.dup
        metrics_copy[:average_response_time] = if (@metrics[:total_requests]).positive?
                                                 @metrics[:total_response_time] / @metrics[:total_requests]
                                               else
                                                 0.0
                                               end
        metrics_copy
      end
    end

    # Gracefully shutdown the delivery engine
    def shutdown
      @connection_pool.shutdown
    end

    # Access to circuit breaker for testing
    attr_reader :circuit_breaker, :connection_pool

    private

    def perform_delivery(event_data, retry_count)
      payload_result = prepare_payload(event_data)
      headers = build_headers(payload_result)

      @connection_pool.with_connection do |http|
        uri = URI.parse(@config.delivery.endpoint)
        path = uri.path.empty? ? '/' : uri.path
        request = Net::HTTP::Post.new(path)
        headers.each { |key, value| request[key] = value }
        request.body = payload_result.payload

        response = http.request(request)

        if response.code.to_i == 200
          DeliveryResult.new(
            success: true,
            status_code: response.code.to_i,
            retry_count: retry_count,
            compressed: payload_result.compressed
          )
        else
          # Return failure result for all non-200 status codes
          # Don't raise exceptions for HTTP status errors
          DeliveryResult.new(
            success: false,
            status_code: response.code.to_i,
            error: response.body,
            retry_count: retry_count,
            compressed: payload_result.compressed
          )
        end
      end
    rescue Timeout::Error => e
      raise "timeout: #{e.message}"
    rescue StandardError => e
      raise "network error: #{e.message}"
    end

    def perform_batch_delivery(payload, event_count)
      headers = build_headers(payload)

      @connection_pool.with_connection do |http|
        uri = URI.parse(@config.delivery.endpoint)
        path = uri.path.empty? ? '/' : uri.path
        request = Net::HTTP::Post.new(path)
        headers.each { |key, value| request[key] = value }
        request.body = payload

        response = http.request(request)

        if response.code.to_i == 200
          DeliveryResult.new(
            success: true,
            status_code: response.code.to_i,
            delivered_count: event_count
          )
        elsif response.code.to_i == 207
          # Partial success - parse response for individual results
          parse_batch_response(response.body, event_count)
        else
          DeliveryResult.new(
            success: false,
            status_code: response.code.to_i,
            error: response.body,
            failed_count: event_count
          )
        end
      end
    rescue Timeout::Error => e
      raise "timeout: #{e.message}"
    rescue StandardError => e
      raise "network error: #{e.message}"
    end

    def prepare_payload(event_data)
      json_data = event_data.to_json

      if should_compress?(json_data)
        compressed_data = Zlib::Deflate.deflate(json_data)
        OpenStruct.new(success: true, compressed: true, payload: compressed_data)
      else
        OpenStruct.new(success: true, compressed: false, payload: json_data)
      end
    end

    def prepare_batch_payload(events)
      json_data = events.to_json

      if should_compress?(json_data)
        Zlib::Deflate.deflate(json_data)
      else
        json_data
      end
    end

    def should_compress?(data)
      return false unless @config.performance.compression_enabled
      return false unless @config.performance.compression_threshold

      data.bytesize > @config.performance.compression_threshold
    end

    def build_headers(payload)
      headers = {
        'Content-Type' => 'application/json',
        'User-Agent' => "EzlogsRubyAgent/#{EzlogsRubyAgent::VERSION}",
        'X-Ezlogs-Agent' => 'ruby',
        'X-Ezlogs-Version' => EzlogsRubyAgent::VERSION,
        'X-Ezlogs-Service' => @config.service_name,
        'X-Ezlogs-Environment' => @config.environment
      }

      headers['Content-Encoding'] = 'gzip' if payload.respond_to?(:compressed) && payload.compressed
      headers.merge!(@config.delivery.headers) if @config.delivery.headers

      headers
    end

    def parse_batch_response(response_body, total_count)
      results = JSON.parse(response_body)
      successful_count = 0
      failed_count = 0

      results['results'].each do |result|
        if result['status'] == 'success'
          successful_count += 1
        else
          failed_count += 1
        end
      end

      DeliveryResult.new(
        success: failed_count.zero?,
        status_code: 207,
        delivered_count: successful_count,
        failed_count: failed_count
      )
    rescue JSON::ParserError
      DeliveryResult.new(
        success: false,
        status_code: 207,
        error: 'Invalid response format',
        failed_count: total_count
      )
    end

    def record_metrics(success, response_time, retry_count)
      @metrics_mutex.synchronize do
        @metrics[:total_requests] += 1
        @metrics[:total_response_time] += response_time
        @metrics[:total_retries] += retry_count

        if success
          @metrics[:successful_requests] += 1
        else
          @metrics[:failed_requests] += 1
        end
      end
    end

    def extract_status_code(error_message)
      return unless error_message =~ /HTTP (\d+)/

      ::Regexp.last_match(1).to_i
    end

    def retryable_error?(status_code)
      RETRYABLE_STATUSES.include?(status_code)
    end
  end
end
