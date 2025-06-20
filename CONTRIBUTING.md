# Contributing to EZLogs Ruby Agent

Thank you for your interest in contributing to EZLogs Ruby Agent! We're building the world's most elegant Rails event tracking gem, and your contributions help make it even better.

## 🎯 How to Contribute

### Types of Contributions

We welcome all types of contributions:

- **🐛 Bug Reports** - Help us identify and fix issues
- **✨ Feature Requests** - Suggest new features and improvements
- **📝 Documentation** - Improve guides, examples, and API docs
- **🧪 Tests** - Add test coverage and improve reliability
- **🔧 Code** - Submit pull requests for bug fixes and features
- **💡 Ideas** - Share your thoughts on the project direction

### Before You Start

1. **Check existing issues** - Your idea might already be discussed
2. **Read the documentation** - Understand the current implementation
3. **Join the discussion** - Share your ideas in GitHub Discussions
4. **Start small** - Begin with documentation or tests

## 🚀 Development Setup

### Prerequisites

- Ruby 3.0 or higher
- Rails 5.0 or higher
- Git

### Local Setup

```bash
# Clone the repository
git clone https://github.com/dezsirazvan/ezlogs_ruby_agent.git
cd ezlogs_ruby_agent

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linting
bundle exec rubocop

# Generate documentation
bundle exec yard doc
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test files
bundle exec rspec spec/ezlogs_ruby_agent/configuration_spec.rb

# Run tests with coverage
COVERAGE=true bundle exec rspec

# Run performance tests
bundle exec rspec spec/performance/

# Run security tests
bundle exec rspec spec/security/
```

### Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix RuboCop issues
bundle exec rubocop -a

# Run RSpec
bundle exec rspec

# Check test coverage
open coverage/index.html
```

## 📝 Code Style

### Ruby Style Guide

We follow the [Ruby Style Guide](https://github.com/rubocop/ruby-style-guide) and use RuboCop for enforcement:

- Use 2 spaces for indentation
- Use snake_case for methods and variables
- Use CamelCase for classes and modules
- Use UPPER_CASE for constants
- Prefer single quotes for strings unless interpolation is needed
- Use keyword arguments for methods with multiple parameters

### Rails Conventions

- Follow Rails conventions and patterns
- Use Rails naming conventions
- Leverage ActiveSupport utilities when appropriate
- Keep controllers thin and models focused

### Documentation Standards

- Use YARD for API documentation
- Include realistic examples in docstrings
- Document all public methods and classes
- Keep README and guides up to date

## 🧪 Testing Guidelines

### Test Coverage Requirements

- **100% test coverage** for all new code
- **Unit tests** for individual classes and methods
- **Integration tests** for cross-component interactions
- **Performance tests** for critical paths
- **Security tests** for data protection features

### Test Structure

```ruby
# spec/ezlogs_ruby_agent/example_spec.rb
RSpec.describe EzlogsRubyAgent::Example do
  describe '#method_name' do
    context 'when condition is met' do
      it 'performs expected behavior' do
        # Arrange
        instance = described_class.new
        
        # Act
        result = instance.method_name
        
        # Assert
        expect(result).to eq(expected_value)
      end
    end
    
    context 'when condition is not met' do
      it 'handles error gracefully' do
        # Test error scenarios
      end
    end
  end
end
```

### Test Best Practices

- Use descriptive test names that explain the behavior
- Test both success and failure scenarios
- Mock external dependencies
- Use factories for test data
- Keep tests focused and isolated

## 🔧 Pull Request Process

### Before Submitting

1. **Fork the repository** on GitHub
2. **Create a feature branch** from `master`
3. **Make your changes** following the style guide
4. **Add tests** for new functionality
5. **Update documentation** if needed
6. **Run the test suite** and ensure all tests pass
7. **Check code quality** with RuboCop

### Pull Request Guidelines

1. **Use descriptive titles** that explain the change
2. **Reference related issues** in the description
3. **Include a summary** of changes made
4. **Add screenshots** for UI changes
5. **Update documentation** if API changes are made
6. **Ensure CI passes** before requesting review

### Example Pull Request

```markdown
## Description
Adds support for custom event validation in the configuration system.

## Changes
- Added `validate_events` option to CollectConfiguration
- Added `required_event_fields` array for validation
- Added validation logic in EventProcessor
- Added comprehensive tests for validation features

## Testing
- [x] Added unit tests for validation logic
- [x] Added integration tests for configuration
- [x] Updated documentation with examples
- [x] All existing tests pass

## Related Issues
Closes #123
```

## 🐛 Bug Reports

### Bug Report Template

```markdown
## Bug Description
A clear description of what the bug is.

## Steps to Reproduce
1. Go to '...'
2. Click on '...'
3. Scroll down to '...'
4. See error

## Expected Behavior
What you expected to happen.

## Actual Behavior
What actually happened.

## Environment
- Ruby version: [e.g., 3.2.0]
- Rails version: [e.g., 7.0.0]
- EZLogs version: [e.g., 0.1.19]
- Operating system: [e.g., macOS 13.0]

## Additional Context
Any other context about the problem.
```

## ✨ Feature Requests

### Feature Request Template

```markdown
## Feature Description
A clear description of the feature you'd like to see.

## Problem Statement
What problem does this feature solve?

## Proposed Solution
How would you like this feature to work?

## Alternative Solutions
Any alternative solutions you've considered.

## Additional Context
Any other context, examples, or screenshots.
```

## 📚 Documentation

### Documentation Guidelines

- **Keep it simple** - Write for developers of all skill levels
- **Include examples** - Show real-world usage patterns
- **Be comprehensive** - Cover all features and options
- **Stay current** - Update docs when features change
- **Use clear language** - Avoid jargon and technical terms

### Documentation Structure

```
docs/
├── getting-started.md      # Quick start guide
├── configuration.md        # Configuration options
├── performance.md          # Performance tuning
├── security.md            # Security features
├── testing.md             # Testing strategies
└── api/                   # API documentation
    ├── classes/           # Class documentation
    ├── modules/           # Module documentation
    └── methods/           # Method documentation
```

## 🎯 Development Priorities

### Current Focus Areas

1. **Performance Optimization** - Maintain sub-1ms overhead
2. **Security Enhancement** - Improve PII detection and sanitization
3. **Developer Experience** - Better debugging and testing tools
4. **Documentation** - Comprehensive guides and examples
5. **Testing** - Improve test coverage and reliability

### Contribution Ideas

- **Performance improvements** - Optimize event processing
- **Security features** - Add new PII detection patterns
- **Testing tools** - Create better test helpers
- **Documentation** - Improve guides and examples
- **Examples** - Create more example applications
- **Monitoring** - Add health checks and metrics

## 🤝 Community Guidelines

### Code of Conduct

We are committed to providing a welcoming and inclusive environment for all contributors. Please:

- **Be respectful** - Treat others with kindness and respect
- **Be constructive** - Provide helpful feedback and suggestions
- **Be inclusive** - Welcome contributors of all backgrounds
- **Be patient** - Understand that everyone has different skill levels

### Communication

- **GitHub Issues** - For bug reports and feature requests
- **GitHub Discussions** - For questions and general discussion
- **Pull Requests** - For code contributions
- **Email** - For sensitive or private matters

## 🏆 Recognition

### Contributors

We recognize all contributors in our:

- **README.md** - List of major contributors
- **CHANGELOG.md** - Credit for significant contributions
- **GitHub Contributors** - Automatic recognition on GitHub

### Types of Recognition

- **Code Contributors** - Direct code contributions
- **Documentation Contributors** - Documentation improvements
- **Bug Reporters** - Helpful bug reports
- **Feature Requesters** - Valuable feature suggestions
- **Community Members** - Active participation in discussions

## 📞 Getting Help

### Resources

- **[Documentation](https://dezsirazvan.github.io/ezlogs_ruby_agent/)** - Complete API reference
- **[GitHub Issues](https://github.com/dezsirazvan/ezlogs_ruby_agent/issues)** - Bug reports and feature requests
- **[GitHub Discussions](https://github.com/dezsirazvan/ezlogs_ruby_agent/discussions)** - Questions and general discussion
- **[Examples](../examples/)** - Working example applications

### Contact

- **Maintainer** - dezsirazvan@gmail.com
- **GitHub** - [@dezsirazvan](https://github.com/dezsirazvan)
- **Discussions** - [GitHub Discussions](https://github.com/dezsirazvan/ezlogs_ruby_agent/discussions)

## 🎉 Thank You

Thank you for contributing to EZLogs Ruby Agent! Your contributions help make this gem better for the entire Ruby community. Every contribution, no matter how small, is valuable and appreciated.

Together, we're building the world's most elegant Rails event tracking gem! 🚀

---

**Ready to contribute?** Start by checking out the [issues](https://github.com/dezsirazvan/ezlogs_ruby_agent/issues) or joining the [discussion](https://github.com/dezsirazvan/ezlogs_ruby_agent/discussions)! 