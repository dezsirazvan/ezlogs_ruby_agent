require_relative "lib/ezlogs_ruby_agent/version"

Gem::Specification.new do |spec|
  spec.name = "ezlogs_ruby_agent"
  spec.version = EzlogsRubyAgent::VERSION
  spec.authors = ["dezsirazvan"]
  spec.email = ["dezsirazvan@gmail.com"]

  spec.summary = "The world's most elegant Rails event tracking gem - Zero-impact instrumentation that powers AI-driven business insights"
  spec.description = <<~DESC
    EZLogs Ruby Agent transforms your Rails application into an intelligent event-tracking powerhouse.#{' '}
    With sub-1ms overhead and zero impact on your application's performance, it captures every meaningful#{' '}
    interaction and delivers it to your analytics platform for AI-powered insights.

    Features:
    • Zero Performance Impact - Sub-1ms overhead per event
    • Complete Visibility - HTTP requests, database changes, background jobs
    • Enterprise Security - Automatic PII detection and sanitization
    • Developer Experience - Zero-config setup with rich debugging tools
    • Business Process Tracking - Correlate events across complex workflows
    • Production Ready - Thread-safe, memory-efficient, and fault-tolerant
  DESC

  spec.homepage = "https://github.com/dezsirazvan/ezlogs_ruby_agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile examples/ benchmark/])
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "activejob", ">= 5.0"
  spec.add_dependency "activerecord", ">= 5.0"
  spec.add_dependency "activesupport", ">= 5.0"
  spec.add_dependency "rack", ">= 2.0"
  spec.add_dependency "rails", ">= 5.0"
  spec.add_dependency "sidekiq", ">= 6.0" if defined?(Sidekiq)

  # Development dependencies
  spec.add_development_dependency "factory_bot_rails", "~> 6.0"
  spec.add_development_dependency "faker", "~> 3.0"
  spec.add_development_dependency "github-markup", "~> 4.0"
  spec.add_development_dependency "redcarpet", "~> 3.5"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
  spec.add_development_dependency "simplecov", "~> 0.21"
  spec.add_development_dependency "yard", "~> 0.9"

  # Metadata
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/dezsirazvan/ezlogs_ruby_agent",
    "changelog_uri" => "https://github.com/dezsirazvan/ezlogs_ruby_agent/blob/master/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/dezsirazvan/ezlogs_ruby_agent/issues",
    "documentation_uri" => "https://dezsirazvan.github.io/ezlogs_ruby_agent/",
    "mailing_list_uri" => "https://github.com/dezsirazvan/ezlogs_ruby_agent/discussions",
    "wiki_uri" => "https://github.com/dezsirazvan/ezlogs_ruby_agent/wiki",
    "funding_uri" => "https://github.com/sponsors/dezsirazvan",
    "rubygems_mfa_required" => "true"
  }

  # Platform support
  spec.platform = Gem::Platform::RUBY
  spec.required_rubygems_version = Gem::Requirement.new(">= 0") if spec.respond_to? :required_rubygems_version=

  # Gem signing (when available)
  spec.metadata["rubygems_mfa_required"] = "true" if spec.respond_to? :metadata

  # Post install message
  spec.post_install_message = <<~MESSAGE
    🚀 Thanks for installing EZLogs Ruby Agent!

    Quick start:
    1. Add to your Gemfile: gem 'ezlogs_ruby_agent'
    2. Run: bundle install
    3. Create config/initializers/ezlogs_ruby_agent.rb:

       EzlogsRubyAgent.configure do |c|
         c.service_name = 'my-app'
         c.environment = Rails.env
       end

    4. Restart your Rails app and start tracking events!

    📚 Documentation: https://dezsirazvan.github.io/ezlogs_ruby_agent/
    🐛 Issues: https://github.com/dezsirazvan/ezlogs_ruby_agent/issues
    💬 Discussions: https://github.com/dezsirazvan/ezlogs_ruby_agent/discussions

    Transform your Rails app into an intelligent, observable system! 🎯
  MESSAGE
end
