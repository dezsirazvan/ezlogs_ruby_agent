require 'digest'
require 'json'

module EzlogsRubyAgent
  # Custom exception for payload size errors
  class PayloadTooLargeError < StandardError; end

  # EventProcessor handles security, sampling, validation, and processing pipeline
  # for all events in the EzlogsRubyAgent system. It provides comprehensive PII
  # protection, payload size validation, and smart sampling capabilities.
  #
  # @example Basic usage
  #   processor = EventProcessor.new
  #   result = processor.process(event)
  #
  # @example With custom configuration
  #   processor = EventProcessor.new(
  #     sample_rate: 0.1,
  #     max_payload_size: 32 * 1024,
  #     sanitize_fields: ['password', 'token'],
  #     auto_detect_pii: true
  #   )
  class EventProcessor
    # Default PII patterns for automatic detection
    DEFAULT_PII_PATTERNS = {
      'credit_card' => /\b(?:\d{4}[-\s]?){3}\d{4}\b/,
      'ssn' => /\b\d{3}-?\d{2}-?\d{4}\b/,
      'phone' => /\b\(?(\d{3})\)?[-.\s]?(\d{3})[-.\s]?(\d{4})\b/,
      'email_loose' => /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/
    }.freeze

    # Common sensitive field names to sanitize
    DEFAULT_SENSITIVE_FIELDS = %w[
      password passwd pwd secret token api_key access_key
      credit_card cc_number card_number ssn social_security
      auth_token session_id cookie
    ].freeze

    # Processor version for tracking
    VERSION = '1.0.0'.freeze

    # Initialize the event processor with configuration options
    #
    # @param sample_rate [Float] Sampling rate (0.0 to 1.0)
    # @param max_payload_size [Integer] Maximum payload size in bytes
    # @param auto_detect_pii [Boolean] Whether to automatically detect PII
    # @param sanitize_fields [Array<String>] Field names to sanitize
    # @param custom_patterns [Hash] Custom regex patterns for PII detection
    # @param deterministic_sampling [Boolean] Use deterministic sampling based on event ID
    def initialize(sample_rate: 1.0, max_payload_size: 64 * 1024,
                   auto_detect_pii: true, sanitize_fields: [],
                   custom_patterns: {}, deterministic_sampling: false)
      @sample_rate = sample_rate
      @max_payload_size = max_payload_size
      @auto_detect_pii = auto_detect_pii
      @sanitize_fields = sanitize_fields
      @custom_patterns = custom_patterns
      @deterministic_sampling = deterministic_sampling
      @pii_patterns = DEFAULT_PII_PATTERNS.merge(@custom_patterns)
    end

    # Process an event through the security and validation pipeline
    #
    # @param event [UniversalEvent] The event to process
    # @return [Hash, nil] Processed event hash or nil if filtered out
    # @raise [PayloadTooLargeError] If event exceeds size limit
    def process(event)
      # Apply sampling filter first
      return nil unless sample?(event.event_id)

      # Convert to hash for processing and deep copy to allow modification
      event_hash = deep_copy(event.to_h)

      # Validate payload size
      validate_payload_size!(event_hash)

      # Apply security sanitization
      sanitized_fields = apply_sanitization!(event_hash)

      # Add processing metadata
      add_processing_metadata!(event_hash, sanitized_fields)

      event_hash
    end

    private

    # Determine if event should be sampled
    #
    # @param event_id [String] Event ID for deterministic sampling
    # @return [Boolean] Whether to include this event
    def sample?(event_id = nil)
      return true if @sample_rate >= 1.0
      return false if @sample_rate <= 0.0

      if @deterministic_sampling && event_id
        # Deterministic sampling based on event ID hash
        hash = Digest::SHA256.hexdigest(event_id.to_s)
        hash_int = hash[0, 8].to_i(16)
        (hash_int.to_f / 0xFFFFFFFF) < @sample_rate
      else
        # Random sampling
        rand < @sample_rate
      end
    end

    # Validate that the event payload doesn't exceed size limits
    #
    # @param event_hash [Hash] Event data
    # @raise [PayloadTooLargeError] If payload is too large
    def validate_payload_size!(event_hash)
      payload_size = JSON.generate(event_hash).bytesize

      return unless payload_size > @max_payload_size

      raise PayloadTooLargeError,
            "Event payload (#{payload_size} bytes) exceeds maximum size (#{@max_payload_size} bytes)"
    end

    # Apply security sanitization to the event data
    #
    # @param event_hash [Hash] Event data to sanitize
    # @return [Array<String>] List of sanitized field paths
    def apply_sanitization!(event_hash)
      sanitized_fields = []

      # Apply field-based sanitization
      sanitized_fields.concat(sanitize_by_field_names!(event_hash))

      # Apply pattern-based PII detection
      sanitized_fields.concat(sanitize_by_patterns!(event_hash)) if @auto_detect_pii

      sanitized_fields
    end

    # Sanitize based on field names
    #
    # @param event_hash [Hash] Event data
    # @return [Array<String>] Sanitized field paths
    def sanitize_by_field_names!(event_hash)
      sanitized_fields = []
      all_sensitive_fields = DEFAULT_SENSITIVE_FIELDS + @sanitize_fields

      sanitize_hash_recursive!(event_hash, all_sensitive_fields, sanitized_fields)
      sanitized_fields
    end

    # Sanitize based on PII patterns
    #
    # @param event_hash [Hash] Event data
    # @return [Array<String>] Sanitized field paths
    def sanitize_by_patterns!(event_hash)
      sanitized_fields = []

      detect_pii_recursive!(event_hash, sanitized_fields)
      sanitized_fields
    end

    # Recursively sanitize hash based on field names
    #
    # @param hash [Hash] Hash to sanitize
    # @param sensitive_fields [Array<String>] Field names to sanitize
    # @param sanitized_fields [Array<String>] Accumulator for sanitized field paths
    # @param path [String] Current path in the hash
    def sanitize_hash_recursive!(hash, sensitive_fields, sanitized_fields, path = '')
      hash.each do |key, value|
        current_path = path.empty? ? key.to_s : "#{path}.#{key}"

        if sensitive_fields.any? { |field| key.to_s.downcase.include?(field.downcase) }
          hash[key] = '[REDACTED]'
          sanitized_fields << current_path
        elsif value.is_a?(Hash)
          sanitize_hash_recursive!(value, sensitive_fields, sanitized_fields, current_path)
        elsif value.is_a?(Array)
          value.each_with_index do |item, index|
            if item.is_a?(Hash)
              sanitize_hash_recursive!(item, sensitive_fields, sanitized_fields, "#{current_path}[#{index}]")
            end
          end
        end
      end
    end

    # Recursively detect PII patterns in hash values
    #
    # @param hash [Hash] Hash to scan
    # @param sanitized_fields [Array<String>] Accumulator for sanitized field paths
    # @param path [String] Current path in the hash
    def detect_pii_recursive!(hash, sanitized_fields, path = '')
      hash.each do |key, value|
        current_path = path.empty? ? key.to_s : "#{path}.#{key}"

        if value.is_a?(String)
          @pii_patterns.each do |pattern_name, pattern|
            next unless value.match?(pattern)

            hash[key] = '[REDACTED]'
            sanitized_fields << current_path
            break
          end
        elsif value.is_a?(Hash)
          detect_pii_recursive!(value, sanitized_fields, current_path)
        elsif value.is_a?(Array)
          value.each_with_index do |item, index|
            if item.is_a?(Hash)
              detect_pii_recursive!(item, sanitized_fields, "#{current_path}[#{index}]")
            elsif item.is_a?(String)
              @pii_patterns.each do |pattern_name, pattern|
                next unless item.match?(pattern)

                value[index] = '[REDACTED]'
                sanitized_fields << "#{current_path}[#{index}]"
                break
              end
            end
          end
        end
      end
    end

    # Add processing metadata to the event
    #
    # @param event_hash [Hash] Event data
    # @param sanitized_fields [Array<String>] List of sanitized fields
    def add_processing_metadata!(event_hash, sanitized_fields)
      event_hash[:processing] = {
        processed_at: Time.now.utc,
        processor_version: VERSION,
        sanitized_fields: sanitized_fields,
        sample_rate: @sample_rate,
        security_applied: sanitized_fields.any? || @auto_detect_pii
      }
    end

    # Create a deep copy of a hash structure
    #
    # @param obj [Object] Object to copy
    # @return [Object] Deep copy of the object
    def deep_copy(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), copy| copy[k] = deep_copy(v) }
      when Array
        obj.map { |item| deep_copy(item) }
      else
        begin
          obj.dup
        rescue StandardError
          obj
        end
      end
    end
  end
end
