# Project: ezlogs-ruby gem

This gem sends structured activity events from a Ruby/Rails app to a local or remote server (typically Go-based) via HTTP, ensuring non-blocking logging and event capture. It is public, open-source, and meant to be the most reliable and developer-friendly logging gem available.

## 🎯 Objectives
- Fast and safe for production
- Beautiful developer experience (DX)
- Idiomatic Ruby style
- Resilient to network issues (retry/fallback)
- Easily testable with full RSpec coverage
- Supports buffering, background flushing
- Modular, extensible, and easy to read
- Secure and zero PII leakage by default

## 🤖 AI Instructions (Global)
Always:
- Use TDD: start with test, then make it pass
- Follow RubyGems conventions (`lib/ezlogs_ruby_agent/...`, versioning, gemspec)
- Avoid premature abstractions
- Prefer service objects and POROs
- Handle errors gracefully, fail silently unless critical
- Use `Faraday` or Net::HTTP as appropriate, but async-safe
- Add docs and clear commit messages