require 'benchmark/ips'
require 'memory_profiler'
require 'concurrent'
require 'time'
require_relative '../lib/ezlogs_ruby_agent'

module EzlogsRubyAgent
  # Comprehensive performance benchmark suite for production validation
  class PerformanceSuite
    def initialize
      @config = Configuration.new
      @config.service_name = 'benchmark-app'
      @config.environment = 'test'
      @config.freeze!

      @processor = EventProcessor.new
      @writer = EventWriter.new(@config)
    end

    def run_all_benchmarks
      puts '🚀 EzlogsRubyAgent Performance Validation Suite'
      puts '=' * 60

      benchmark_event_creation
      benchmark_correlation_management
      benchmark_event_processing
      benchmark_memory_usage
      benchmark_concurrent_load
      benchmark_delivery_engine
      benchmark_integration_flow

      puts "\n✅ All benchmarks completed!"
    end

    private

    def benchmark_event_creation
      puts "\n📊 Event Creation Performance (< 0.5ms target)"
      puts '-' * 40

      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report('UniversalEvent creation') { create_minimal_event }
        x.report('UniversalEvent with full data') { create_full_event }
        x.report('Event with correlation') { create_correlated_event }
        x.report('Event with metadata') { create_event_with_metadata }

        x.compare!
      end

      # Validate 95th percentile
      validate_percentile_performance
    end

    def benchmark_correlation_management
      puts "\n🔗 Correlation Management Performance"
      puts '-' * 40

      Benchmark.ips do |x|
        x.config(time: 3, warmup: 1)

        x.report('Start request context') do
          CorrelationManager.start_request_context('req_123', 'sess_456')
          CorrelationManager.clear_context
        end

        x.report('Get current context') { CorrelationManager.current_context }
        x.report('Extract correlation data') { CorrelationManager.extract_correlation_data }

        x.compare!
      end
    end

    def benchmark_event_processing
      puts "\n⚙️ Event Processing Performance"
      puts '-' * 40

      event = create_full_event

      Benchmark.ips do |x|
        x.config(time: 3, warmup: 1)

        x.report('Event processing') { @processor.process(event) }
        x.report('Event serialization') { event.to_h }
        x.report('Event validation') { event.valid? }

        x.compare!
      end
    end

    def benchmark_memory_usage
      puts "\n💾 Memory Usage Validation (< 5KB per event)"
      puts '-' * 40

      # Test memory usage for 1000 events
      report = MemoryProfiler.report do
        1000.times do |i|
          event = UniversalEvent.new(
            event_type: 'test.memory',
            action: "action_#{i}",
            actor: { type: 'test', id: i.to_s },
            metadata: {
              field1: "value_#{i}",
              field2: { nested: "data_#{i}" },
              field3: Array.new(10) { |j| "item_#{i}_#{j}" }
            }
          )
          @processor.process(event)
        end
      end

      total_memory = report.total_allocated_memsize
      memory_per_event = total_memory / 1000.0

      puts "Total memory allocated: #{format_bytes(total_memory)}"
      puts "Memory per event: #{format_bytes(memory_per_event)}"
      puts 'Target: < 5KB per event'
      puts "Status: #{memory_per_event < 5 * 1024 ? '✅ PASS' : '❌ FAIL'}"
    end

    def benchmark_concurrent_load
      puts "\n🔄 Concurrent Load Testing (> 20k events/sec)"
      puts '-' * 40

      thread_counts = [1, 4, 8, 16]

      thread_counts.each do |thread_count|
        puts "\nTesting with #{thread_count} threads:"

        start_time = Time.now
        events_processed = 0

        threads = thread_count.times.map do
          Thread.new do
            1000.times do |i|
              event = UniversalEvent.new(
                event_type: 'test.concurrent',
                action: "action_#{i}",
                actor: { type: 'test', id: i.to_s },
                metadata: { thread_id: Thread.current.object_id, iteration: i }
              )
              @processor.process(event)
              events_processed += 1
            end
          end
        end

        threads.each(&:join)
        end_time = Time.now

        duration = end_time - start_time
        throughput = events_processed / duration

        puts "  Events processed: #{events_processed}"
        puts "  Duration: #{duration.round(3)}s"
        puts "  Throughput: #{throughput.round(0)} events/sec"
        puts "  Status: #{throughput > 20_000 ? '✅ PASS' : '❌ FAIL'}"
      end
    end

    def benchmark_delivery_engine
      puts "\n📡 Delivery Engine Performance"
      puts '-' * 40

      # Create a mock delivery engine for testing
      engine = DeliveryEngine.new(@config)

      Benchmark.ips do |x|
        x.config(time: 3, warmup: 1)

        event_data = create_full_event.to_h

        x.report('Payload preparation') { engine.send(:prepare_payload, event_data) }
        x.report('Headers building') { engine.send(:build_headers, 'test payload') }
        x.report('Compression check') { engine.send(:should_compress?, 'test data') }

        x.compare!
      end
    end

    def benchmark_integration_flow
      puts "\n🔄 Complete Integration Flow Performance"
      puts '-' * 40

      # Simulate complete HTTP → DB → Job flow
      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report('Complete flow simulation') do
          # HTTP request
          CorrelationManager.start_request_context('req_123', 'sess_456')
          http_event = UniversalEvent.new(
            event_type: 'http.request',
            action: 'GET /users/123',
            actor: { type: 'user', id: '456' },
            subject: { type: 'user', id: '123' },
            metadata: { status: 200, duration: 0.150 }
          )

          # Database change
          db_event = UniversalEvent.new(
            event_type: 'data.change',
            action: 'user.updated',
            actor: { type: 'user', id: '456' },
            subject: { type: 'user', id: '123' },
            metadata: { changes: { email: ['old@test.com', 'new@test.com'] } }
          )

          # Background job
          job_event = UniversalEvent.new(
            event_type: 'job.execution',
            action: 'welcome_email.send',
            actor: { type: 'system', id: 'job_processor' },
            subject: { type: 'email', id: 'welcome_123' },
            metadata: { status: 'completed', duration: 0.250 }
          )

          # Process all events
          [http_event, db_event, job_event].each { |e| @processor.process(e) }

          CorrelationManager.clear_context
        end

        x.compare!
      end
    end

    def validate_percentile_performance
      puts "\n📈 95th Percentile Performance Validation"
      puts '-' * 40

      times = []
      1000.times do
        start_time = Time.now
        create_full_event
        end_time = Time.now
        times << (end_time - start_time) * 1000 # Convert to ms
      end

      times.sort!
      p95_time = times[950] # 95th percentile
      p99_time = times[990] # 99th percentile
      avg_time = times.sum / times.length

      puts "Average time: #{avg_time.round(3)}ms"
      puts "95th percentile: #{p95_time.round(3)}ms"
      puts "99th percentile: #{p99_time.round(3)}ms"
      puts 'Target: < 0.5ms for 95th percentile'
      puts "Status: #{p95_time < 0.5 ? '✅ PASS' : '❌ FAIL'}"
    end

    # Helper methods for creating test events
    def create_minimal_event
      UniversalEvent.new(
        event_type: 'test.minimal',
        action: 'test',
        actor: { type: 'test', id: '1' }
      )
    end

    def create_full_event
      UniversalEvent.new(
        event_type: 'test.full',
        action: 'complete.test',
        actor: { type: 'user', id: '123', email: 'user@example.com' },
        subject: { type: 'resource', id: '456', name: 'Test Resource' },
        metadata: {
          field1: 'value1',
          field2: { nested: 'data' },
          field3: %w[item1 item2 item3],
          timestamp: Time.now.iso8601,
          duration: 0.150,
          status: 'success'
        }
      )
    end

    def create_correlated_event
      CorrelationManager.start_request_context('req_123', 'sess_456')
      event = UniversalEvent.new(
        event_type: 'test.correlated',
        action: 'correlated.test',
        actor: { type: 'user', id: '123' },
        subject: { type: 'resource', id: '456' }
      )
      CorrelationManager.clear_context
      event
    end

    def create_event_with_metadata
      UniversalEvent.new(
        event_type: 'test.metadata',
        action: 'metadata.test',
        actor: { type: 'system', id: 'processor' },
        metadata: {
          large_field: 'x' * 1000,
          complex_data: {
            nested: {
              deep: {
                value: 'very deep data',
                array: Array.new(50) { |i| "item_#{i}" }
              }
            }
          }
        }
      )
    end

    def format_bytes(bytes)
      if bytes < 1024
        "#{bytes} B"
      elsif bytes < 1024 * 1024
        "#{(bytes / 1024.0).round(2)} KB"
      else
        "#{(bytes / (1024.0 * 1024.0)).round(2)} MB"
      end
    end
  end
end

# Run the benchmark suite if this file is executed directly
if __FILE__ == $0
  suite = EzlogsRubyAgent::PerformanceSuite.new
  suite.run_all_benchmarks
end
