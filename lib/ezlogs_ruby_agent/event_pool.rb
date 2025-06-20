module EzlogsRubyAgent
  # EventPool provides object pooling for frequently created objects
  # to optimize memory usage and reduce allocation overhead in high-throughput
  # scenarios.
  #
  # @example Using the event pool
  #   event = EventPool.get_event
  #   begin
  #     # Use the event
  #     event.event_type = "http.request"
  #     # ... configure event
  #   ensure
  #     EventPool.return_event(event)
  #   end
  class EventPool
    # Default pool configuration
    DEFAULT_POOL_SIZE = 100
    DEFAULT_MAX_POOL_SIZE = 1000

    class << self
      # Get an event object from the pool
      #
      # @return [UniversalEvent] Event object from pool or newly created
      def get_event
        pool = get_pool
        begin
          pool.pop(true)
        rescue ThreadError
          # Pool is empty, create new event
          create_new_event
        end
      end

      # Return an event object to the pool
      #
      # @param event [UniversalEvent] Event to return to pool
      def return_event(event)
        return unless event.is_a?(UniversalEvent)

        pool = get_pool
        return if pool.size >= max_pool_size

        # Reset the event for reuse
        reset_event(event)
        pool.push(event)
      rescue ThreadError
        # Pool is full, discard the event
      end

      # Get pool statistics
      #
      # @return [Hash] Pool statistics
      def pool_stats
        pool = get_pool
        {
          pool_size: pool.size,
          max_pool_size: max_pool_size,
          created_count: @created_count || 0,
          reused_count: @reused_count || 0
        }
      end

      # Clear the pool
      def clear_pool
        pool = get_pool
        pool.clear
        @created_count = 0
        @reused_count = 0
      end

      private

      def get_pool
        @get_pool ||= Queue.new
      end

      def max_pool_size
        @max_pool_size ||= DEFAULT_MAX_POOL_SIZE
      end

      def create_new_event
        @created_count ||= 0
        @created_count += 1
        UniversalEvent.new(
          event_type: 'pool.placeholder',
          action: 'placeholder',
          actor: { type: 'system', id: 'pool' }
        )
      end

      def reset_event(event)
        # Reset event to a clean state for reuse
        # Note: UniversalEvent is immutable, so we create a new one
        # This method is a placeholder for future optimization
      end
    end
  end

  # BatchProcessor provides optimized batch processing with compression
  # and memory management for high-throughput event delivery.
  #
  # @example Processing a batch of events
  #   processor = BatchProcessor.new
  #   result = processor.process_batch(events)
  class BatchProcessor
    # Default batch configuration
    DEFAULT_BATCH_SIZE = 100
    DEFAULT_MAX_BATCH_SIZE = 1000
    DEFAULT_COMPRESSION_THRESHOLD = 1024 # bytes

    def initialize(batch_size: DEFAULT_BATCH_SIZE,
                   max_batch_size: DEFAULT_MAX_BATCH_SIZE,
                   compression_threshold: DEFAULT_COMPRESSION_THRESHOLD)
      @batch_size = batch_size
      @max_batch_size = max_batch_size
      @compression_threshold = compression_threshold
      @batch_buffer = []
      @batch_mutex = Mutex.new
    end

    # Process a batch of events with optimization
    #
    # @param events [Array<UniversalEvent>] Events to process
    # @return [Hash] Processing result with metadata
    def process_batch(events)
      return { success: true, processed: 0, compressed: false } if events.empty?

      start_time = Time.now
      processed_events = []

      events.each do |event|
        processed = process_single_event(event)
        processed_events << processed if processed
      end

      # Optimize batch for delivery
      optimized_batch = optimize_batch(processed_events)

      end_time = Time.now
      processing_time = (end_time - start_time).to_f

      {
        success: true,
        processed: processed_events.size,
        batch_size: optimized_batch.size,
        processing_time: processing_time,
        compressed: optimized_batch[:compressed] || false,
        batch_data: optimized_batch
      }
    rescue StandardError => e
      {
        success: false,
        error: e.message,
        processed: 0,
        processing_time: (Time.now - start_time).to_f
      }
    end

    # Add event to batch buffer
    #
    # @param event [UniversalEvent] Event to add
    # @return [Boolean] Whether batch is ready for processing
    def add_to_batch(event)
      @batch_mutex.synchronize do
        @batch_buffer << event
        @batch_buffer.size >= @batch_size
      end
    end

    # Get and clear current batch
    #
    # @return [Array<UniversalEvent>] Current batch
    def get_current_batch
      @batch_mutex.synchronize do
        batch = @batch_buffer.dup
        @batch_buffer.clear
        batch
      end
    end

    private

    def process_single_event(event)
      return nil unless event.is_a?(UniversalEvent) && event.valid?

      # Convert to hash for processing
      event.to_h
    rescue StandardError => e
      warn "[Ezlogs] Failed to process event: #{e.message}"
      nil
    end

    def optimize_batch(events)
      return { events: [], compressed: false } if events.empty?

      # Convert to JSON for size analysis
      json_data = events.to_json
      data_size = json_data.bytesize

      if data_size > @compression_threshold
        # Compress the batch
        compressed_data = compress_data(json_data)
        {
          events: compressed_data,
          compressed: true,
          original_size: data_size,
          compressed_size: compressed_data.bytesize
        }
      else
        {
          events: events,
          compressed: false,
          size: data_size
        }
      end
    end

    def compress_data(data)
      require 'zlib'
      Zlib::Deflate.deflate(data)
    rescue LoadError
      # Zlib not available, return uncompressed
      data
    end
  end

  # ConnectionManager provides optimized connection lifecycle management
  # for HTTP delivery with connection pooling and health monitoring.
  #
  # @example Using connection manager
  #   manager = ConnectionManager.new(endpoint, max_connections: 10)
  #   manager.with_connection do |connection|
  #     # Use connection for HTTP requests
  #   end
  class ConnectionManager
    def initialize(endpoint, max_connections: 10, timeout: 30)
      @endpoint = endpoint
      @max_connections = max_connections
      @timeout = timeout
      @connection_pool = Queue.new
      @active_connections = 0
      @mutex = Mutex.new
      @closed = false
    end

    # Get a connection from the pool
    #
    # @yield [Net::HTTP] Connection object
    # @return [Object] Result of the block
    def with_connection
      connection = checkout_connection
      begin
        yield connection
      ensure
        checkin_connection(connection) unless @closed
      end
    end

    # Get connection pool statistics
    #
    # @return [Hash] Pool statistics
    def pool_stats
      @mutex.synchronize do
        {
          pool_size: @connection_pool.size,
          active_connections: @active_connections,
          max_connections: @max_connections,
          closed: @closed
        }
      end
    end

    # Close all connections and shutdown the pool
    def shutdown
      @mutex.synchronize do
        @closed = true
        until @connection_pool.empty?
          begin
            conn = @connection_pool.pop(true)
            conn.finish if conn.started?
          rescue ThreadError
            break
          end
        end
      end
    end

    private

    def checkout_connection
      return create_connection if @connection_pool.empty?

      begin
        @connection_pool.pop(true)
      rescue ThreadError
        create_connection
      end
    end

    def checkin_connection(connection)
      return if @closed || !connection.started?

      @mutex.synchronize do
        if @connection_pool.size < @max_connections
          @connection_pool.push(connection)
        else
          connection.finish
        end
      end
    rescue ThreadError
      # Pool is full, close the connection
      connection.finish
    end

    def create_connection
      @mutex.synchronize do
        @active_connections += 1
      end

      uri = URI.parse(@endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http
    rescue StandardError => e
      @mutex.synchronize do
        @active_connections -= 1
      end
      raise e
    end
  end
end
