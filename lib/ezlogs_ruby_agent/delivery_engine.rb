require 'net/http'
require 'net/https'
require 'zlib'
require 'json'
require 'thread'
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
          # Check if we should attempt reset
          raise 'Circuit breaker open' unless should_attempt_reset?

          @state = :half_open
        end
      end

      begin
        result = yield
        record_success
        result
      rescue StandardError => e
        record_failure
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

    def record_success
      @mutex.synchronize do
        @state = :closed
        @failure_count = 0
        @last_failure_time = nil
      end
    end

    def record_failure
      @mutex.synchronize do
        @failure_count += 1
        @last_failure_time = Time.now

        @state = :open if @failure_count >= @threshold
      end
    end

    def should_attempt_reset?
      return false unless open?
      return false unless @last_failure_time

      Time.now - @last_failure_time >= @timeout
    end

    def attempt_reset
      @mutex.synchronize do
        if should_attempt_reset?
          @state = :half_open
          true
        else
          false
        end
      end
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
        @config.performance.max_concurrent_connections,
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
      retry_count = 0

      begin
        @circuit_breaker.call do
          loop do
            result = perform_delivery(event_data, retry_count)

            # If successful, return immediately
            if result.success?
              record_metrics(true, Time.now - start_time, retry_count)
              return result
            end

            # If the result indicates failure, we need to raise an exception
            # to trigger the circuit breaker failure tracking
            raise "HTTP #{result.status_code}: #{result.error}" if result.failure?

            record_metrics(true, Time.now - start_time, retry_count)
            return result
          rescue StandardError => e
            retry_count += 1

            if retry_count > @config.delivery.retry_attempts
              record_metrics(false, Time.now - start_time, retry_count)
              return DeliveryResult.new(
                success: false,
                status_code: extract_status_code(e.message),
                error: e.message,
                retry_count: retry_count,
                response_time: Time.now - start_time
              )
            end

            # Only retry on retryable errors
            unless e.message.include?('HTTP 500') || e.message.include?('HTTP 502') ||
                   e.message.include?('HTTP 503') || e.message.include?('HTTP 504') ||
                   e.message.include?('HTTP 408') || e.message.include?('HTTP 429')
              # Non-retryable error, return immediately
              record_metrics(false, Time.now - start_time, retry_count)
              return DeliveryResult.new(
                success: false,
                status_code: extract_status_code(e.message),
                error: e.message,
                retry_count: retry_count,
                response_time: Time.now - start_time
              )
            end

            # Exponential backoff
            sleep(@config.delivery.retry_backoff**retry_count)
          end
        end
      rescue StandardError => e
        record_metrics(false, Time.now - start_time, retry_count)
        error_message = e.message.include?('Circuit breaker open') ? e.message : "Circuit breaker: #{e.message}"
        DeliveryResult.new(
          success: false,
          error: error_message,
          retry_count: retry_count,
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
        error_message = e.message.include?('Circuit breaker open') ? e.message : "Circuit breaker: #{e.message}"
        DeliveryResult.new(
          success: false,
          error: error_message,
          response_time: Time.now - start_time
        )
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
        average_response_time: if @metrics[:total_requests] > 0
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
        metrics_copy[:average_response_time] = if @metrics[:total_requests] > 0
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
        request = Net::HTTP::Post.new(URI.parse(@config.delivery.endpoint).path)
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
        elsif RETRYABLE_STATUSES.include?(response.code.to_i)
          raise "HTTP #{response.code}: #{response.body}"
        else
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
        request = Net::HTTP::Post.new(URI.parse(@config.delivery.endpoint).path)
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
        'User-Agent' => "EzlogsRubyAgent/#{EzlogsRubyAgent::VERSION}"
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
        success: failed_count == 0,
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
      if error_message =~ /HTTP (\d+)/
        ::Regexp.last_match(1).to_i
      else
        nil
      end
    end
  end
end
