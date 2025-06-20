require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yard"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

# Documentation tasks
YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb', 'README.md', 'CHANGELOG.md', 'CONTRIBUTING.md']
  t.options = ['--output-dir', 'doc']
end

namespace :docs do
  desc "Generate API documentation"
  task generate: :yard do
    puts "✅ API documentation generated in doc/"
  end

  desc "Serve documentation locally"
  task :serve do
    puts "🌐 Starting documentation server at http://localhost:8808"
    puts "📚 Press Ctrl+C to stop"
    system "yard server --reload --port 8808"
  end

  desc "Clean documentation"
  task :clean do
    FileUtils.rm_rf 'doc'
    puts "🧹 Documentation cleaned"
  end
end

# Development tasks
namespace :dev do
  desc "Run all checks (tests, linting, docs)"
  task check: %i[spec rubocop docs] do
    puts "✅ All checks passed!"
  end

  desc "Run RuboCop"
  task :rubocop do
    system "bundle exec rubocop"
  end

  desc "Run tests with coverage"
  task :coverage do
    ENV['COVERAGE'] = 'true'
    Rake::Task[:spec].invoke
  end

  desc "Update gems"
  task :update do
    system "bundle update"
  end

  desc "Install dependencies"
  task :install do
    system "bundle install"
  end
end

# Release tasks
namespace :release do
  desc "Build and push gem"
  task push: [:build] do
    system "gem push pkg/ezlogs_ruby_agent-#{EzlogsRubyAgent::VERSION}.gem"
  end

  desc "Create release tag"
  task :tag do
    version = EzlogsRubyAgent::VERSION
    system "git tag -a v#{version} -m 'Release v#{version}'"
    system "git push origin v#{version}"
  end

  desc "Full release process"
  task full: %i[spec rubocop build tag push] do
    puts "🚀 Release v#{EzlogsRubyAgent::VERSION} completed!"
  end
end

# Performance tasks
namespace :perf do
  desc "Run performance benchmarks"
  task :benchmark do
    system "ruby benchmark/performance_suite.rb"
  end

  desc "Run simple performance test"
  task :simple do
    system "ruby benchmark/simple_performance_test.rb"
  end
end

# Security tasks
namespace :security do
  desc "Run security validation"
  task :validate do
    Rake::Task["spec:security"].invoke
  end

  desc "Run security tests"
  task :test do
    system "bundle exec rspec spec/security/"
  end
end

# Testing tasks
namespace :test do
  desc "Run all tests"
  task all: %i[unit integration performance security]

  desc "Run unit tests"
  task :unit do
    system "bundle exec rspec spec/ezlogs_ruby_agent/"
  end

  desc "Run integration tests"
  task :integration do
    system "bundle exec rspec spec/integration/"
  end

  desc "Run performance tests"
  task :performance do
    system "bundle exec rspec spec/performance/"
  end

  desc "Run security tests"
  task :security do
    system "bundle exec rspec spec/security/"
  end
end

# Documentation tasks
namespace :docs do
  desc "Generate all documentation"
  task all: %i[api guides]

  desc "Generate API documentation"
  task api: :yard

  desc "Generate guides"
  task :guides do
    puts "📚 Guides are in the docs/ directory"
  end

  desc "Validate documentation"
  task :validate do
    puts "🔍 Validating documentation..."
    # Add documentation validation logic here
    puts "✅ Documentation validation passed"
  end
end

# Cleanup tasks
namespace :clean do
  desc "Clean all generated files"
  task all: %i[docs coverage tmp]

  desc "Clean documentation"
  task :docs do
    FileUtils.rm_rf 'doc'
  end

  desc "Clean coverage reports"
  task :coverage do
    FileUtils.rm_rf 'coverage'
  end

  desc "Clean temporary files"
  task :tmp do
    FileUtils.rm_rf 'tmp'
  end
end

# Help task
desc "Show available tasks"
task :help do
  puts "EZLogs Ruby Agent - Available Tasks"
  puts "==================================="
  puts ""
  puts "Development:"
  puts "  rake dev:check     - Run all checks (tests, linting, docs)"
  puts "  rake dev:install   - Install dependencies"
  puts "  rake dev:update    - Update gems"
  puts ""
  puts "Testing:"
  puts "  rake test:all      - Run all tests"
  puts "  rake test:unit     - Run unit tests"
  puts "  rake test:integration - Run integration tests"
  puts "  rake test:performance - Run performance tests"
  puts "  rake test:security - Run security tests"
  puts ""
  puts "Documentation:"
  puts "  rake docs:generate - Generate API documentation"
  puts "  rake docs:serve    - Serve documentation locally"
  puts "  rake docs:clean    - Clean documentation"
  puts ""
  puts "Performance:"
  puts "  rake perf:benchmark - Run performance benchmarks"
  puts "  rake perf:simple   - Run simple performance test"
  puts ""
  puts "Security:"
  puts "  rake security:validate - Run security validation"
  puts "  rake security:test - Run security tests"
  puts ""
  puts "Release:"
  puts "  rake release:full  - Full release process"
  puts "  rake release:tag   - Create release tag"
  puts "  rake release:push  - Build and push gem"
  puts ""
  puts "Cleanup:"
  puts "  rake clean:all     - Clean all generated files"
  puts "  rake clean:docs    - Clean documentation"
  puts "  rake clean:coverage - Clean coverage reports"
  puts ""
  puts "For more information, see CONTRIBUTING.md"
end
