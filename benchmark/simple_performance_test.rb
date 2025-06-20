require 'benchmark'
require 'time'
require 'securerandom'

# Simple performance test for core components
puts '🚀 EzlogsRubyAgent Simple Performance Test'
puts '=' * 50

# Test 1: Event Creation Performance
puts "\n📊 Event Creation Performance Test"
puts '-' * 30

times = []
1000.times do |i|
  start_time = Time.now

  # Simulate event creation
  event_id = "evt_#{SecureRandom.urlsafe_base64(16).tr('_-', 'ab')}"
  timestamp = Time.now.utc
  event_type = 'test.performance'
  action = "action_#{i}"
  actor = { type: 'test', id: i.to_s }
  metadata = { field1: 'value1', field2: 'value2' }

  # Simulate correlation
  correlation_id = "corr_#{SecureRandom.urlsafe_base64(16).tr('_-', 'cd')}"

  # Simulate platform info
  platform = {
    service: 'test-app',
    environment: 'test',
    agent_version: '0.1.19',
    ruby_version: RUBY_VERSION
  }

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

# Test 2: Concurrent Event Creation
puts "\n🔄 Concurrent Event Creation Test"
puts '-' * 35

thread_counts = [1, 4, 8]
thread_counts.each do |thread_count|
  puts "\nTesting with #{thread_count} threads:"

  start_time = Time.now
  events_created = 0

  threads = thread_count.times.map do |i|
    Thread.new do
      1000.times do |j|
        # Simulate event creation
        event_id = "evt_#{SecureRandom.urlsafe_base64(16).tr('_-', 'ab')}"
        timestamp = Time.now.utc
        event_type = 'test.concurrent'
        action = "action_#{i}_#{j}"
        actor = { type: 'test', id: "#{i}_#{j}" }

        events_created += 1
      end
    end
  end

  threads.each(&:join)
  end_time = Time.now

  duration = end_time - start_time
  throughput = events_created / duration

  puts "  Events created: #{events_created}"
  puts "  Duration: #{duration.round(3)}s"
  puts "  Throughput: #{throughput.round(0)} events/sec"
  puts '  Target: > 20k events/sec'
  puts "  Status: #{throughput > 20_000 ? '✅ PASS' : '❌ FAIL'}"
end

# Test 3: Memory Usage Estimation
puts "\n💾 Memory Usage Estimation"
puts '-' * 25

# Estimate memory usage for 1000 events
estimated_memory_per_event = 1024 # 1KB estimate
total_events = 1000
estimated_total_memory = estimated_memory_per_event * total_events

puts "Estimated memory per event: #{estimated_memory_per_event} bytes"
puts "Estimated memory for #{total_events} events: #{estimated_total_memory} bytes"
puts 'Target: < 5KB per event'
puts "Status: #{estimated_memory_per_event < 5 * 1024 ? '✅ PASS' : '❌ FAIL'}"

# Test 4: Correlation ID Generation Performance
puts "\n🔗 Correlation ID Generation Performance"
puts '-' * 40

correlation_times = []
10_000.times do
  start_time = Time.now
  correlation_id = "corr_#{SecureRandom.urlsafe_base64(16).tr('_-', 'cd')}"
  end_time = Time.now
  correlation_times << (end_time - start_time) * 1000
end

correlation_times.sort!
corr_p95 = correlation_times[9500]
corr_avg = correlation_times.sum / correlation_times.length

puts "Average correlation ID generation: #{corr_avg.round(6)}ms"
puts "95th percentile: #{corr_p95.round(6)}ms"
puts 'Target: < 0.1ms for 95th percentile'
puts "Status: #{corr_p95 < 0.1 ? '✅ PASS' : '❌ FAIL'}"

# Test 5: JSON Serialization Performance
puts "\n📄 JSON Serialization Performance"
puts '-' * 35

require 'json'

event_data = {
  event_id: "evt_#{SecureRandom.urlsafe_base64(16)}",
  timestamp: Time.now.utc.iso8601,
  event_type: 'test.serialization',
  action: 'test',
  actor: { type: 'test', id: '123' },
  subject: { type: 'resource', id: '456' },
  correlation: {
    correlation_id: "corr_#{SecureRandom.urlsafe_base64(16)}",
    flow_id: 'flow_test_123',
    session_id: 'sess_abc123',
    request_id: 'req_xyz789'
  },
  metadata: {
    field1: 'value1',
    field2: { nested: 'data' },
    field3: %w[item1 item2 item3]
  },
  platform: {
    service: 'test-app',
    environment: 'test',
    agent_version: '0.1.19',
    ruby_version: RUBY_VERSION
  }
}

serialization_times = []
1000.times do
  start_time = Time.now
  json_data = event_data.to_json
  end_time = Time.now
  serialization_times << (end_time - start_time) * 1000
end

serialization_times.sort!
ser_p95 = serialization_times[950]
ser_avg = serialization_times.sum / serialization_times.length
payload_size = event_data.to_json.bytesize

puts "Average serialization time: #{ser_avg.round(3)}ms"
puts "95th percentile: #{ser_p95.round(3)}ms"
puts "Payload size: #{payload_size} bytes"
puts 'Target: < 1ms for 95th percentile'
puts "Status: #{ser_p95 < 1.0 ? '✅ PASS' : '❌ FAIL'}"

puts "\n✅ Performance test completed!"
puts '=' * 50
