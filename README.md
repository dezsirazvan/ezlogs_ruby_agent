# EzlogsRubyAgent

A zero-impact instrumentation gem for Rails apps.  
Collects HTTP requests, ActiveRecord callbacks, and background job metrics—and ships them to a lightweight local agent for batching and delivery.

## Features

- **HTTP Tracking**  
  Instruments every Rack request: path, params, status, duration, error messages.

- **ActiveRecord Callbacks**  
  Captures `create`, `update`, and `destroy` on your models (configurable by resource).

- **Background Job Tracking**  
  Supports ActiveJob and Sidekiq for job start, success, failure, duration, and arguments.

- **In-Process, Non-Blocking Sender**  
  Events are enqueued in memory and sent over TCP in the background—no delays in your web or job threads.

- **Pluggable Actor Extraction**  
  Define how to extract “who” performed each action (e.g. current user).

- **Simple Configuration**  
  Enable or disable any capture, whitelist or blacklist resources, and tune buffer sizes and intervals.

## Installation

Add to your Gemfile:

```ruby
gem 'ezlogs_ruby_agent'
bundle install
```


## Setup
 - **Install & run the local Go agent**  
   Follow the Go agent README to install the standalone binary and start it as a service on port 9000.
 - **Configure the gem**  
   Create ```config/initializers/ezlogs_ruby_agent.rb```
   ```ruby
   EzlogsRubyAgent.configure do |c|
    # What to capture
    c.capture_http        = true
    c.capture_callbacks   = true
    c.capture_jobs        = true

    # Optional: restrict to certain models or jobs
    c.resources_to_track  = ['User', 'order']
    c.exclude_resources   = ['Admin']

    # How to extract "actor" (current user)
    c.actor_extractor     = ->(context) { context.current_user&.id }

    # Local agent settings
    c.agent_host          = ENV.fetch('EZLOGS_AGENT_HOST', '127.0.0.1')
    c.agent_port          = ENV.fetch('EZLOGS_AGENT_PORT', 9000).to_i
    c.flush_interval      = 1.0        # seconds
    c.max_buffer_size     = 5_000      # events
   end
   ```
  - **Restart your Rails app**  
    The Railtie will automatically insert the HTTP middleware and include the AR and Job trackers.

## Usage

Events flow through your system like this:  
[Your App Threads] ──log(event)──▶ [EventWriter Queue] ──(batch TCP)──▶ [Local Go Agent]
                                          │
                                          ▼ (background, non-blocking)
                        
[Local Go Agent] ──(HTTP POST with API key)──▶ [EZLogs Remote Collector API]

- **Your application** calls EzlogsRubyAgent.writer.log(event_hash) in the background.  
- **EventWriter** buffers and TCP-sends them to ```127.0.0.1:9000``` without blocking. 
- **Go agent** receives, batches, and forwards via HTTPS to your collector endpoint using your API key.

## Contributing

We welcome bug reports and PRs to make Ezlogs even better!

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
