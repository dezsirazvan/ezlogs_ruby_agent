# EzlogsRubyAgent

# Ezlogs Ruby Agent

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
1. Install & run the local Go agent

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/ezlogs_ruby_agent.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
