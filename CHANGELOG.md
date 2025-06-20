# Changelog

All notable changes to EZLogs Ruby Agent will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive documentation suite with guides and examples
- Professional gemspec with complete metadata
- Contributing guidelines and community standards
- Example applications demonstrating all features
- YARD API documentation for all public methods

### Changed
- Enhanced README with conversion-focused content
- Improved gemspec with proper dependencies and metadata
- Updated configuration system with better validation

## [0.1.19] - 2024-01-15

### Added
- **Performance Monitoring** - Built-in performance metrics and monitoring
- **Health Status** - System health checks for all components
- **Debug Tools** - Enhanced debugging capabilities for development
- **Test Mode** - Comprehensive testing support with in-memory capture
- **Correlation Manager** - Business process tracking across services
- **Event Pool** - Memory-efficient event storage and management

### Changed
- **Configuration System** - Enhanced DSL with nested configuration objects
- **Security Features** - Improved PII detection and sanitization
- **Performance** - Optimized event processing for sub-1ms overhead
- **Thread Safety** - Enhanced concurrent operation support

### Fixed
- Memory leaks in long-running applications
- Thread safety issues in high-concurrency scenarios
- Configuration validation edge cases
- Event delivery reliability improvements

## [0.1.18] - 2024-01-10

### Added
- **Actor Extraction** - Configurable user identification
- **Field Filtering** - Whitelist/blacklist for event fields
- **Payload Limits** - Configurable size restrictions
- **Retry Logic** - Automatic retry for failed deliveries
- **Connection Pooling** - Efficient network connection management

### Changed
- **Event Structure** - Standardized event format
- **Error Handling** - Improved error recovery and logging
- **Performance** - Reduced memory footprint per event

### Fixed
- Network timeout handling
- Memory usage optimization
- Configuration loading issues

## [0.1.17] - 2024-01-05

### Added
- **PII Detection** - Automatic sensitive data identification
- **Data Sanitization** - Configurable data protection methods
- **Security Configuration** - Comprehensive security settings
- **Compliance Features** - GDPR, CCPA, and HIPAA support

### Changed
- **Security First** - Enhanced data protection by default
- **Configuration Validation** - Stricter configuration checks
- **Error Messages** - More descriptive error reporting

### Fixed
- Security vulnerabilities in data handling
- Configuration validation edge cases
- Error message clarity

## [0.1.16] - 2024-01-01

### Added
- **Background Job Tracking** - ActiveJob and Sidekiq support
- **Job Middleware** - Automatic job instrumentation
- **Job Metrics** - Duration, success/failure tracking
- **Queue Monitoring** - Job queue performance metrics

### Changed
- **Job Integration** - Seamless background job tracking
- **Performance** - Optimized job event processing
- **Error Handling** - Better job failure tracking

### Fixed
- Job event correlation issues
- Memory usage in job processing
- Thread safety in job tracking

## [0.1.15] - 2023-12-25

### Added
- **Database Change Tracking** - ActiveRecord callback instrumentation
- **Model Events** - Create, update, destroy tracking
- **Change Detection** - Field-level change tracking
- **Resource Filtering** - Selective model tracking

### Changed
- **Database Integration** - Enhanced ActiveRecord support
- **Event Granularity** - More detailed database events
- **Performance** - Optimized database event processing

### Fixed
- Database event performance impact
- Change detection accuracy
- Memory usage in database tracking

## [0.1.14] - 2023-12-20

### Added
- **HTTP Request Tracking** - Rack middleware for request instrumentation
- **Request Metrics** - Duration, status, and metadata tracking
- **Path Filtering** - Selective request tracking
- **Response Monitoring** - Response time and error tracking

### Changed
- **HTTP Integration** - Seamless request tracking
- **Performance** - Minimal overhead for HTTP tracking
- **Error Handling** - Better error response tracking

### Fixed
- HTTP event performance impact
- Request correlation issues
- Memory usage in HTTP tracking

## [0.1.13] - 2023-12-15

### Added
- **Event Writer** - Thread-safe event queuing system
- **Delivery Engine** - Background event delivery
- **Event Processing** - Event transformation and filtering
- **Buffer Management** - Intelligent event buffering

### Changed
- **Architecture** - Improved event processing pipeline
- **Performance** - Better event throughput
- **Reliability** - Enhanced event delivery guarantees

### Fixed
- Event loss in high-throughput scenarios
- Memory usage optimization
- Thread safety improvements

## [0.1.12] - 2023-12-10

### Added
- **Configuration System** - Flexible configuration DSL
- **Environment Support** - Environment-specific settings
- **Validation** - Configuration validation and error checking
- **Documentation** - Comprehensive configuration guides

### Changed
- **Configuration** - More intuitive configuration API
- **Error Handling** - Better configuration error messages
- **Flexibility** - More configuration options

### Fixed
- Configuration loading issues
- Environment variable handling
- Validation error reporting

## [0.1.11] - 2023-12-05

### Added
- **Universal Event** - Standardized event structure
- **Event Types** - HTTP, database, job, and custom events
- **Event Metadata** - Rich event context and data
- **Event Correlation** - Cross-event relationship tracking

### Changed
- **Event Structure** - Consistent event format
- **Event Types** - Better event categorization
- **Metadata** - Enhanced event context

### Fixed
- Event structure consistency
- Metadata handling
- Event correlation accuracy

## [0.1.10] - 2023-12-01

### Added
- **Rails Integration** - Railtie for automatic Rails setup
- **Middleware Support** - Rack middleware integration
- **ActiveRecord Integration** - Model callback support
- **ActiveJob Integration** - Background job support

### Changed
- **Rails Support** - Enhanced Rails integration
- **Setup Process** - Simplified Rails setup
- **Integration** - Better framework integration

### Fixed
- Rails integration issues
- Middleware compatibility
- Framework integration bugs

## [0.1.9] - 2023-11-25

### Added
- **Core Event Tracking** - Basic event logging functionality
- **Event API** - Simple event logging interface
- **Event Storage** - In-memory event storage
- **Basic Configuration** - Simple configuration options

### Changed
- **Core Functionality** - Stable event tracking foundation
- **API Design** - Clean and intuitive API
- **Performance** - Basic performance optimizations

### Fixed
- Core functionality bugs
- API consistency issues
- Performance bottlenecks

## [0.1.0] - 2023-11-20

### Added
- **Initial Release** - First public release of EZLogs Ruby Agent
- **Basic Event Tracking** - Core event logging capabilities
- **Rails Support** - Basic Rails integration
- **Documentation** - Initial documentation and guides

### Changed
- **Project Foundation** - Established project structure
- **Code Quality** - High-quality, well-tested codebase
- **Documentation** - Comprehensive documentation

### Fixed
- Initial release issues
- Documentation accuracy
- Code quality standards

---

## Version History

### Version Numbering

We use [Semantic Versioning](https://semver.org/) for version numbers:

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

### Release Schedule

- **Patch releases** (0.1.x) - Bug fixes and minor improvements
- **Minor releases** (0.x.0) - New features and enhancements
- **Major releases** (x.0.0) - Breaking changes and major updates

### Deprecation Policy

- Deprecated features are marked in documentation
- Deprecated features continue to work for at least one minor version
- Migration guides are provided for breaking changes

---

## Contributors

### Core Team

- **dezsirazvan** - Project maintainer and lead developer

### Community Contributors

- *Add your name here by contributing!*

### Special Thanks

- Ruby community for inspiration and feedback
- Rails team for the excellent framework
- All beta testers and early adopters

---

## Support

### Getting Help

- **[Documentation](https://dezsirazvan.github.io/ezlogs_ruby_agent/)** - Complete API reference
- **[GitHub Issues](https://github.com/dezsirazvan/ezlogs_ruby_agent/issues)** - Bug reports and feature requests
- **[GitHub Discussions](https://github.com/dezsirazvan/ezlogs_ruby_agent/discussions)** - Questions and general discussion

### Migration Guides

- [Migrating from 0.1.18 to 0.1.19](docs/migration/0.1.18-to-0.1.19.md)
- [Migrating from 0.1.17 to 0.1.18](docs/migration/0.1.17-to-0.1.18.md)

---

**EZLogs Ruby Agent** - The world's most elegant Rails event tracking gem! 🚀
