require 'ezlogs_ruby_agent/event_writer'
require 'ezlogs_ruby_agent/actor_extractor'
require 'ezlogs_ruby_agent/universal_event'
require 'ezlogs_ruby_agent/correlation_manager'

module EzlogsRubyAgent
  class SidekiqJobTracker
    def call(worker, job, _queue)
      config = EzlogsRubyAgent.config
      job_name = worker.class.name

      # Extract and restore correlation context
      correlation_data = extract_correlation_data(job)
      correlation_context = nil

      begin
        # Restore correlation context for the job execution
        correlation_context = if correlation_data && correlation_data[:correlation_id]
                                CorrelationManager.inherit_context(correlation_data)
                              else
                                # Fallback: create new context if none available
                                CorrelationManager.start_flow_context('job', job['jid'], {
                                  job_class: job_name,
                                  queue: job['queue']
                                })
                              end
      rescue StandardError => e
        warn "[EzlogsRubyAgent] Failed to restore correlation context: #{e.message}"
        # Create minimal context as fallback
        correlation_context = CorrelationManager.start_flow_context('job', job['jid'], {
          job_class: job_name,
          queue: job['queue'],
          error: e.message
        })
      end

      return yield unless trackable_job?(job_name, config)

      start_time = Time.now
      enqueued_at = extract_enqueued_at(job)

      # Track resource consumption before execution
      memory_before_mb = measure_memory_usage
      gc_count_before = GC.stat[:count]

      # Store timing context for comprehensive tracking
      Thread.current[:ezlogs_sidekiq_start_time] = start_time
      Thread.current[:ezlogs_sidekiq_memory_before] = memory_before_mb
      Thread.current[:ezlogs_sidekiq_gc_before] = gc_count_before
      Thread.current[:ezlogs_sidekiq_job] = job
      Thread.current[:ezlogs_sidekiq_worker] = worker
      Thread.current[:ezlogs_external_calls] = []
      Thread.current[:ezlogs_cache_ops] = 0
      Thread.current[:ezlogs_file_ops] = 0

      resource_id = extract_resource_id_from_job(job)
      status = nil
      error_message = nil
      result = nil

      begin
        # Clear any existing correlation context to prevent frozen hash issues
        CorrelationManager.clear_context
        result = yield
        status = 'completed'
      rescue StandardError => e
        status = 'failed'
        error_message = e.message
        raise e
      ensure
        end_time = Time.now
        begin
          event = UniversalEvent.new(
            event_type: 'job.execution',
            action: "#{job_name}.#{status}",
            actor: ActorExtractor.extract_actor(worker),
            subject: {
              type: 'job',
              id: job['jid'],
              queue: job['queue'],
              resource: resource_id
            },
            metadata: build_comprehensive_sidekiq_metadata(
              job_name: job_name,
              arguments: job['args'],
              status: status,
              error_message: error_message,
              result: result,
              start_time: start_time,
              end_time: end_time,
              enqueued_at: enqueued_at,
              job: job,
              worker: worker
            ),
            timing: build_comprehensive_sidekiq_timing(start_time, end_time, enqueued_at),
            correlation_id: correlation_context&.correlation_id || correlation_data[:correlation_id] || job['correlation_id'],
            correlation_context: correlation_context&.to_h
          )
          EzlogsRubyAgent.writer.log(event)
        rescue StandardError => e
          warn "[Ezlogs] failed to create Sidekiq job event: #{e.message}"
        ensure
          # Clean up thread-local storage
          Thread.current[:ezlogs_sidekiq_start_time] = nil
          Thread.current[:ezlogs_sidekiq_memory_before] = nil
          Thread.current[:ezlogs_sidekiq_gc_before] = nil
          Thread.current[:ezlogs_sidekiq_job] = nil
          Thread.current[:ezlogs_sidekiq_worker] = nil
          Thread.current[:ezlogs_external_calls] = nil
          Thread.current[:ezlogs_cache_ops] = nil
          Thread.current[:ezlogs_file_ops] = nil

          CorrelationManager.clear_context
        end
      end
    end

    # Test helper method to build event without executing job
    def build_event(job_hash)
      job_hash['class']&.name || 'UnknownJob'
      resource_id = extract_resource_id_from_job(job_hash)

      UniversalEvent.new(
        event_type: 'sidekiq.job',
        action: 'enqueue',
        actor: {
          type: 'Job',
          id: job_hash['jid']
        },
        subject: {
          type: 'job',
          id: job_hash['jid'],
          queue: job_hash['queue'],
          resource: resource_id
        },
        payload: {
          queue: job_hash['queue'],
          args: job_hash['args']
        },
        correlation_id: job_hash['correlation_id'],
        correlation_context: CorrelationManager.current_context
      )
    end

    # Test helper method to track job without executing
    def track(job_hash)
      event = build_event(job_hash)
      EzlogsRubyAgent.writer.log(event)
    end

    private

    def build_comprehensive_sidekiq_metadata(job_name:, arguments:, status:, error_message:, result:, start_time:,
                                             end_time:, enqueued_at:, job:, worker:)
      {
        # Basic job information
        job_name: job_name,
        arguments: sanitize_sidekiq_arguments(arguments),
        status: status,
        error_message: error_message,
        result: result,
        retry_count: job['retry_count'],
        scheduled_at: job['at'],
        enqueued_at: job['enqueued_at'],

        # Resource consumption
        resources: build_sidekiq_resource_consumption,

        # Work metrics
        work_performed: build_sidekiq_work_metrics,

        # External dependencies
        external_calls: extract_comprehensive_sidekiq_external_calls,

        # Reliability intelligence
        reliability: build_sidekiq_reliability_metrics(status, error_message, job),

        # Queue health
        queue_metrics: build_sidekiq_queue_health_metrics(job)
      }
    end

    def build_comprehensive_sidekiq_timing(start_time, end_time, enqueued_at)
      execution_time_ms = ((end_time - start_time) * 1000).round(3)
      queue_wait_time_ms = enqueued_at ? ((start_time - Time.at(enqueued_at)) * 1000).round(3) : 0
      queue_wait_time_ms = [queue_wait_time_ms, 0].max # Ensure non-negative

      timing = {
        enqueued_at: enqueued_at ? Time.at(enqueued_at).iso8601(3) : nil,
        started_at: start_time.iso8601(3),
        completed_at: end_time.iso8601(3),
        queue_wait_time_ms: queue_wait_time_ms,
        execution_time_ms: execution_time_ms,
        setup_time_ms: estimate_sidekiq_setup_time,
        cleanup_time_ms: estimate_sidekiq_cleanup_time,
        retry_delay_ms: extract_retry_delay_ms
      }

      # Total time including queue wait (match job tracker format)
      timing[:total_time_ms] = queue_wait_time_ms + execution_time_ms if queue_wait_time_ms > 0 && execution_time_ms > 0

      timing.compact
    end

    def build_sidekiq_resource_consumption
      memory_before_mb = Thread.current[:ezlogs_sidekiq_memory_before] || 0
      memory_after_mb = measure_memory_usage
      gc_count_before = Thread.current[:ezlogs_sidekiq_gc_before] || 0
      gc_count_after = GC.stat[:count]

      {
        memory_before_mb: memory_before_mb,
        memory_after_mb: memory_after_mb,
        memory_peak_mb: estimate_peak_memory_usage(memory_before_mb, memory_after_mb),
        cpu_time_ms: estimate_cpu_time_ms,
        io_wait_time_ms: estimate_io_wait_time_ms,
        network_time_ms: estimate_network_time_ms,
        allocations: estimate_allocations,
        gc_runs_triggered: [gc_count_after - gc_count_before, 0].max
      }
    end

    def build_sidekiq_work_metrics
      # Extract work metrics from thread-local storage or estimate
      {
        records_processed: Thread.current[:ezlogs_records_processed] || estimate_records_processed,
        records_created: Thread.current[:ezlogs_records_created] || 0,
        records_updated: Thread.current[:ezlogs_records_updated] || 0,
        records_deleted: Thread.current[:ezlogs_records_deleted] || 0,
        batch_size: Thread.current[:ezlogs_batch_size] || estimate_batch_size,
        batches_completed: Thread.current[:ezlogs_batches_completed] || 1,
        progress_percentage: Thread.current[:ezlogs_progress_percentage] || 100,
        throughput_per_second: calculate_sidekiq_throughput
      }
    end

    def extract_comprehensive_sidekiq_external_calls
      external_calls = Thread.current[:ezlogs_external_calls] || []
      cache_ops = Thread.current[:ezlogs_cache_ops] || 0
      file_ops = Thread.current[:ezlogs_file_ops] || 0

      {
        api_calls: external_calls,
        total_external_time_ms: external_calls.sum { |call| call[:duration_ms] },
        cache_operations: cache_ops,
        file_operations: file_ops
      }
    end

    def build_sidekiq_reliability_metrics(status, error_message, job)
      retry_count = job['retry_count'] || 0
      max_retries = extract_sidekiq_max_retries(job)
      will_retry = status == 'failed' && retry_count < max_retries

      {
        retry_count: retry_count,
        max_retries: max_retries,
        failure_reason: error_message,
        will_retry: will_retry,
        next_retry_at: will_retry ? calculate_next_retry_time(retry_count) : nil,
        dead_job: status == 'failed' && retry_count >= max_retries,
        error_category: classify_sidekiq_error(error_message)
      }
    end

    def build_sidekiq_queue_health_metrics(job)
      queue_name = job['queue'] || 'default'

      {
        queue_name: queue_name,
        queue_size_before: estimate_sidekiq_queue_size_before(queue_name),
        queue_size_after: estimate_sidekiq_queue_size_after(queue_name),
        worker_count: estimate_sidekiq_worker_count,
        queue_latency_ms: calculate_sidekiq_queue_latency_ms(queue_name)
      }
    end

    # Helper methods for Sidekiq-specific estimations

    def estimate_sidekiq_setup_time
      # Sidekiq setup is typically faster than ActiveJob
      Thread.current[:ezlogs_setup_time] || 8.0
    end

    def estimate_sidekiq_cleanup_time
      # Sidekiq cleanup is typically minimal
      Thread.current[:ezlogs_cleanup_time] || 2.0
    end

    def extract_retry_delay_ms
      # Check if this job was a retry
      retry_count = Thread.current[:ezlogs_sidekiq_job]&.dig('retry_count') || 0
      return 0 if retry_count.zero?

      # Sidekiq default retry delay calculation: (retry_count ** 4) + 15 + (rand(30) * (retry_count + 1))
      base_delay = (retry_count**4) + 15
      (base_delay * 1000).round(3) # Convert to milliseconds
    end

    def estimate_records_processed
      # Estimate based on job arguments
      job = Thread.current[:ezlogs_sidekiq_job]
      return 1 unless job&.dig('args')

      args = job['args']
      # Look for common patterns that indicate batch processing
      if args.any? { |arg| arg.is_a?(Array) }
        args.find { |arg| arg.is_a?(Array) }&.size || 1
      elsif args.any? { |arg| arg.is_a?(Hash) && arg.key?('batch_size') }
        args.find { |arg| arg.is_a?(Hash) && arg.key?('batch_size') }['batch_size'] || 1
      else
        1
      end
    end

    def estimate_batch_size
      # Default Sidekiq batch size
      Thread.current[:ezlogs_batch_size] || 50
    end

    def calculate_sidekiq_throughput
      records = Thread.current[:ezlogs_records_processed] || estimate_records_processed
      start_time = Thread.current[:ezlogs_sidekiq_start_time]
      return 0 unless start_time

      execution_time = Time.now - start_time
      return 0 if execution_time <= 0

      (records / execution_time).round(2)
    end

    def extract_sidekiq_max_retries(job)
      # Sidekiq default max retries is 25
      job['retry'] || 25
    end

    def calculate_next_retry_time(retry_count)
      # Sidekiq retry calculation
      delay_seconds = (retry_count**4) + 15 + (rand(30) * (retry_count + 1))
      (Time.now + delay_seconds).iso8601(3)
    end

    def classify_sidekiq_error(error_message)
      return nil unless error_message

      case error_message
      when /ActiveRecord::/
        'database_error'
      when /Redis::/
        'redis_error'
      when /Net::|HTTP::|Timeout::/
        'network_error'
      when /JSON::|NoMethodError/
        'serialization_error'
      when /ArgumentError|TypeError/
        'argument_error'
      else
        'application_error'
      end
    end

    def estimate_sidekiq_queue_size_before(queue_name)
      if defined?(Sidekiq) && Sidekiq.respond_to?(:redis)
        begin
          Sidekiq.redis { |conn| conn.llen("queue:#{queue_name}") }
        rescue StandardError
          10 # Default estimate
        end
      else
        10
      end
    end

    def estimate_sidekiq_queue_size_after(queue_name)
      size_before = estimate_sidekiq_queue_size_before(queue_name)
      [size_before - 1, 0].max
    end

    def estimate_sidekiq_worker_count
      if defined?(Sidekiq) && Sidekiq.respond_to?(:workers)
        begin
          Sidekiq.workers.size
        rescue StandardError
          5
        end
      else
        5
      end
    end

    def calculate_sidekiq_queue_latency_ms(queue_name)
      # Estimate based on queue size and worker count
      queue_size = estimate_sidekiq_queue_size_before(queue_name)
      worker_count = estimate_sidekiq_worker_count
      return 0 if worker_count.zero?

      # Assume average job takes 2 seconds
      estimated_latency_seconds = (queue_size.to_f / worker_count) * 2
      (estimated_latency_seconds * 1000).round(2)
    end

    def sanitize_sidekiq_arguments(arguments)
      return [] unless arguments.is_a?(Array)

      # Use the same sanitization as JobTracker for consistency
      sensitive_fields = EzlogsRubyAgent.config.security&.sensitive_fields || []

      arguments.map do |arg|
        sanitize_sidekiq_argument_value(arg, sensitive_fields)
      end
    end

    def sanitize_sidekiq_argument_value(value, sensitive_fields)
      case value
      when Hash
        sanitize_sidekiq_hash_deeply(value, sensitive_fields)
      when Array
        begin
          value.map { |v| sanitize_sidekiq_argument_value(v, sensitive_fields) }
        rescue FrozenError
          value.to_a.map { |v| sanitize_sidekiq_argument_value(v, sensitive_fields) }
        end
      when String
        if contains_sensitive_data?(value, sensitive_fields)
          '[REDACTED]'
        else
          value.length > 1000 ? "#{value[0..997]}..." : value
        end
      else
        value
      end
    end

    def sanitize_sidekiq_hash_deeply(hash, sensitive_fields)
      return {} unless hash.is_a?(Hash)

      sanitized = {}
      hash.each do |key, value|
        sanitized[key] = if contains_sensitive_data?(key.to_s, sensitive_fields)
                           '[REDACTED]'
                         else
                           sanitize_sidekiq_argument_value(value, sensitive_fields)
                         end
      end
      sanitized
    rescue FrozenError
      # Handle frozen hashes
      {}
    end

    def contains_sensitive_data?(value, sensitive_fields)
      return false unless value.is_a?(String)

      sensitive_fields.any? do |field|
        value.downcase.include?(field.downcase)
      end
    end

    def measure_memory_usage
      if RUBY_PLATFORM.include?('linux')
        `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
      else
        GC.stat[:heap_live_slots] * 40 / (1024 * 1024).to_f
      end
    rescue StandardError
      0
    end

    def estimate_peak_memory_usage(memory_before, memory_after)
      # Peak is typically 1.2-1.5x the final memory usage during execution
      memory_increase = memory_after - memory_before
      memory_after + (memory_increase * 0.3)
    end

    def estimate_cpu_time_ms
      # CPU time is typically 70-90% of wall time for CPU-intensive jobs
      start_time = Thread.current[:ezlogs_sidekiq_start_time]
      return 0 unless start_time

      wall_time_ms = (Time.now - start_time) * 1000
      (wall_time_ms * 0.8).round(3)
    end

    def estimate_io_wait_time_ms
      # I/O wait is typically 10-30% of wall time for I/O intensive jobs
      start_time = Thread.current[:ezlogs_sidekiq_start_time]
      return 0 unless start_time

      wall_time_ms = (Time.now - start_time) * 1000
      (wall_time_ms * 0.15).round(3)
    end

    def estimate_network_time_ms
      # Network time from external calls tracked in thread-local storage
      external_calls = Thread.current[:ezlogs_external_calls] || []
      external_calls.sum { |call| call[:duration_ms] }
    end

    def estimate_allocations
      # Estimate based on GC stats difference
      gc_before = Thread.current[:ezlogs_sidekiq_gc_before] || 0
      gc_after = GC.stat[:count]
      gc_runs = gc_after - gc_before

      # Rough estimate: each GC run cleans up about 10k allocations
      gc_runs * 10_000 + 5_000 # Base allocation estimate
    end

    def extract_enqueued_at(job)
      job['enqueued_at'] || job['created_at']
    end

    def extract_correlation_data(job)
      correlation_data = if job.is_a?(Hash) && job['_correlation_data']
                           job['_correlation_data']
                         elsif job.is_a?(Hash) && job['correlation_id']
                           { correlation_id: job['correlation_id'] }
                         else
                           {}
                         end

      # Handle frozen hashes that might come from Sidekiq/ActiveJob
      return {} unless correlation_data.is_a?(Hash)

      # Create unfrozen copy to prevent FrozenError
      unfrozen_data = {}
      correlation_data.each do |key, value|
        unfrozen_data[key] = value.frozen? ? value.dup : value
      rescue StandardError
        unfrozen_data[key] = value
      end

      unfrozen_data
    rescue StandardError => e
      warn "[Ezlogs] Failed to extract correlation data: #{e.message}"
      {}
    end

    def extract_resource_id_from_job(job)
      return unless job['args'] && job['args'].first.is_a?(Hash)

      job['args'].first[:id] || job['args'].first['id']
    end

    def trackable_job?(job_name, config)
      # Temporarily exclude CreateOutcomeJob due to frozen hash issues
      return false if job_name == 'CreateOutcomeJob'

      resource_match = config.included_resources.empty? ||
                       config.included_resources.map(&:downcase).any? do |resource|
                         job_name.downcase.include?(resource.downcase)
                       end
      excluded_match = config.excluded_resources.map(&:downcase).any? do |resource|
        job_name.downcase.include?(resource.downcase)
      end
      resource_match && !excluded_match
    end
  end
end
