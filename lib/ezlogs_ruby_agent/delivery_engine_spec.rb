it 'resets circuit breaker on successful request' do
  stub_request(:post, 'https://logs.example.com/events')
    .to_return(status: 500)

  # First failure (should fail immediately without retries)
  result = engine.deliver(event_data)
  expect(result.success?).to be false

  # Second request should also fail (no retries when building up to threshold)
  result = engine.deliver(event_data)
  expect(result.success?).to be false

  # Now make a successful request
  stub_request(:post, 'https://logs.example.com/events')
    .to_return(status: 200)

  result = engine.deliver(event_data)
  expect(result.success?).to be true

  # Circuit breaker should be closed
  expect(engine.circuit_breaker.closed?).to be true
end
