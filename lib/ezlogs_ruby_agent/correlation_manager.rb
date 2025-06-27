require 'securerandom'

module EzlogsRubyAgent
  # CorrelationManager provides thread-safe correlation context management
  # across all components in the EzlogsRubyAgent system. It ensures perfect
  # correlation tracking from HTTP requests through database changes to
  # background jobs.
  #
  # @example Starting a request context
  #   CorrelationManager.start_request_context(request_id, session_id)
  #
  # @example Inheriting context in a background job
  #   CorrelationManager.inherit_context(job_correlation_data)
  #
  # @example Getting current context
  #   context = CorrelationManager.current_context
  class CorrelationManager
    # Correlation context structure
    class Context
      attr_reader :correlation_id, :flow_id, :session_id, :request_id,
                  :parent_event_id, :started_at, :metadata

      def initialize(correlation_id: nil, flow_id: nil, session_id: nil,
                     request_id: nil, parent_event_id: nil, started_at: nil, metadata: {})
        @correlation_id = correlation_id || generate_correlation_id
        @flow_id = flow_id || generate_flow_id
        @session_id = session_id
        @request_id = request_id
        @parent_event_id = parent_event_id
        @started_at = started_at || Time.now.utc

        # Safely handle metadata that might be frozen
        @metadata = if metadata.is_a?(Hash)
                      if metadata.frozen?
                        deep_dup_metadata(metadata)
                      else
                        metadata.dup
                      end
                    else
                      {}
                    end
        freeze
      end

      def to_h
        {
          correlation_id: @correlation_id,
          flow_id: @flow_id,
          session_id: @session_id,
          request_id: @request_id,
          parent_event_id: @parent_event_id,
          started_at: @started_at,
          metadata: @metadata
        }.compact
      end

      def merge(other_context)
        return self unless other_context

        # Safely merge metadata, handling frozen hashes
        merged_metadata = begin
          @metadata.merge(other_context.metadata)
        rescue StandardError
          # If merge fails due to frozen hashes, deep duplicate and merge
          safe_metadata = @metadata.frozen? ? deep_dup_metadata(@metadata) : @metadata.dup
          other_metadata = other_context.metadata.frozen? ? deep_dup_metadata(other_context.metadata) : other_context.metadata
          safe_metadata.merge(other_metadata)
        end

        Context.new(
          correlation_id: @correlation_id,
          flow_id: @flow_id,
          session_id: @session_id || other_context.session_id,
          request_id: @request_id || other_context.request_id,
          parent_event_id: @parent_event_id || other_context.parent_event_id,
          metadata: merged_metadata
        )
      end

      private

      def generate_correlation_id
        "corr_#{SecureRandom.urlsafe_base64(16).tr('_-', 'ab')}"
      end

      def generate_flow_id
        "flow_#{SecureRandom.urlsafe_base64(16).tr('_-', 'cd')}"
      end

      # Helper method to safely deep duplicate frozen metadata
      def deep_dup_metadata(metadata)
        return {} unless metadata.is_a?(Hash)

        unfrozen = {}
        metadata.each do |key, value|
          new_key = key.respond_to?(:dup) && !key.is_a?(Symbol) ? key.dup : key
          new_value = case value
                      when Hash
                        deep_dup_metadata(value)
                      when Array
                        value.map { |item| item.is_a?(Hash) ? deep_dup_metadata(item) : item }
                      else
                        value.respond_to?(:dup) && !value.is_a?(Symbol) && !value.is_a?(Numeric) && !value.nil? ? value.dup : value
                      end
          unfrozen[new_key] = new_value
        rescue StandardError
          # If we can't duplicate, just use the original value
          unfrozen[key] = value
        end
        unfrozen
      rescue StandardError
        {}
      end
    end

    # Thread-local storage key
    CONTEXT_KEY = :ezlogs_context

    class << self
      # Start a new request context for HTTP requests
      #
      # @param request_id [String] Unique request identifier
      # @param session_id [String, nil] Session identifier
      # @param metadata [Hash] Additional context metadata
      # @return [Context] The created context
      def start_request_context(request_id, session_id = nil, metadata = {})
        context = Context.new(
          request_id: request_id,
          session_id: session_id,
          metadata: metadata
        )
        set_context(context)
        context
      end

      # Start a new flow context for business processes
      #
      # @param flow_type [String] Type of flow (e.g., 'user_registration')
      # @param entity_id [String] Entity identifier
      # @param metadata [Hash] Additional context metadata
      # @return [Context] The created context
      def start_flow_context(flow_type, entity_id, metadata = {})
        correlation_id = "corr_#{SecureRandom.urlsafe_base64(16).tr('_-', 'ab')}"
        flow_id = "flow_#{flow_type}_#{entity_id}"
        context = Context.new(
          correlation_id: correlation_id,
          flow_id: flow_id,
          metadata: metadata.merge(flow_type: flow_type, entity_id: entity_id)
        )
        set_context(context)
        context
      end

      # Inherit correlation context from parent (for async operations)
      #
      # @param parent_context [Context, Hash] Parent context to inherit from
      # @param metadata [Hash] Additional context metadata
      # @return [Context] The inherited context
      def inherit_context(parent_context, metadata = {})
        return start_flow_context('async', SecureRandom.uuid, metadata) unless parent_context

        parent = parent_context.is_a?(Context) ? parent_context : Context.new(**parent_context)
        current = current_context

        # Merge parent and current contexts
        inherited = if current
                      current.merge(parent)
                    else
                      parent
                    end

        # Add inheritance metadata
        inherited_metadata = inherited.metadata.merge(
          metadata,
          inherited_from: parent.correlation_id,
          inherited_at: Time.now.utc
        )

        # Preserve parent's correlation_id - prioritize metadata correlation_id if explicitly provided
        correlation_id = if parent_context.is_a?(Hash) && parent_context[:correlation_id]
                           parent_context[:correlation_id]
                         elsif inherited.metadata[:correlation_id]
                           inherited.metadata[:correlation_id]
                         elsif parent.respond_to?(:correlation_id) && parent.correlation_id
                           parent.correlation_id
                         else
                           # Generate new correlation ID only if absolutely necessary
                           generate_correlation_id
                         end

        new_context = Context.new(
          correlation_id: correlation_id,
          flow_id: inherited.flow_id,
          session_id: inherited.session_id,
          request_id: inherited.request_id,
          parent_event_id: inherited.parent_event_id,
          metadata: inherited_metadata
        )

        set_context(new_context)
        new_context
      end

      # Get the current correlation context
      #
      # @return [Context, nil] Current context or nil if none exists
      def current_context
        Thread.current[CONTEXT_KEY]
      end

      # Execute a block with a specific context
      #
      # @param context [Context, Hash] Context to use for the block
      # @yield Block to execute with the context
      # @return [Object] Result of the block
      def with_context(context, &block)
        previous_context = current_context

        # Convert context to Context object if it's a hash
        new_context = if context.is_a?(Hash)
                        # Extract known parameters and put the rest in metadata
                        known_params = context.slice(:correlation_id, :flow_id, :session_id, :request_id,
                                                     :parent_event_id)
                        metadata = context.except(*known_params.keys)
                        Context.new(**known_params, metadata: metadata)
                      else
                        context
                      end

        # For Context objects, replace entirely. For hashes, merge with existing context
        final_context = if context.is_a?(Hash) && previous_context && new_context
                          previous_context.merge(new_context)
                        else
                          new_context
                        end

        set_context(final_context)
        block.call
      ensure
        set_context(previous_context)
      end

      # Clear the current correlation context
      def clear_context
        Thread.current[CONTEXT_KEY] = nil
      end

      # Create a child context for a specific event
      #
      # @param event_id [String] ID of the child event
      # @param metadata [Hash] Additional metadata
      # @return [Context] Child context
      def create_child_context(event_id, metadata = {})
        current = current_context
        return start_flow_context('orphaned', SecureRandom.uuid, metadata) unless current

        child_metadata = current.metadata.merge(
          metadata,
          parent_event_id: current.correlation_id,
          child_event_id: event_id
        )

        Context.new(
          correlation_id: current.correlation_id,
          flow_id: current.flow_id,
          session_id: current.session_id,
          request_id: current.request_id,
          parent_event_id: event_id,
          metadata: child_metadata
        )
      end

      # Extract correlation data for serialization (e.g., for job arguments)
      #
      # @return [Hash] Correlation data hash
      def extract_correlation_data
        current = current_context
        return {} unless current

        current.to_h
      end

      # Alias for extract_correlation_data for compatibility
      def extract_context
        extract_correlation_data
      end

      # Restore correlation context from serialized data
      #
      # @param correlation_data [Hash] Serialized correlation data
      # @return [Context] Restored context
      def restore_context(correlation_data)
        return nil unless correlation_data.is_a?(Hash)

        # Create completely unfrozen copy to avoid FrozenError
        unfrozen_data = deep_dup(correlation_data)

        # Ensure all hash keys and values are unfrozen
        unfrozen_data.each do |key, value|
          unfrozen_data[key] = deep_dup(value) if value.frozen? && (value.is_a?(Hash) || value.is_a?(Array))
        end

        context = Context.new(**unfrozen_data)
        set_context(context)
        context
      rescue StandardError => e
        warn "[Ezlogs] Failed to restore correlation context: #{e.message}"
        nil
      end

      # Deep duplicate nested hashes and arrays
      def deep_dup(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), new_hash|
            new_key = key.frozen? && key.respond_to?(:dup) ? key.dup : key
            new_hash[new_key] = deep_dup(value)
          end
        when Array
          obj.map { |item| deep_dup(item) }
        else
          if obj.respond_to?(:duplicable?) && obj.duplicable?
            obj.dup
          elsif obj.respond_to?(:dup) && !obj.frozen?
            obj.dup
          elsif obj.respond_to?(:dup)
            begin
              obj.dup
            rescue StandardError
              obj
            end
          else
            obj
          end
        end
      rescue StandardError
        # Fallback to original object if duplication fails
        obj
      end

      private

      def set_context(context)
        Thread.current[CONTEXT_KEY] = context
      end

      def generate_correlation_id
        "corr_#{SecureRandom.urlsafe_base64(16).tr('_-', 'ab')}"
      end

      # Helper method to safely deep duplicate frozen metadata (class method version)
      def deep_dup_metadata(metadata)
        return {} unless metadata.is_a?(Hash)

        unfrozen = {}
        metadata.each do |key, value|
          new_key = key.respond_to?(:dup) && !key.is_a?(Symbol) ? key.dup : key
          new_value = case value
                      when Hash
                        deep_dup_metadata(value)
                      when Array
                        value.map { |item| item.is_a?(Hash) ? deep_dup_metadata(item) : item }
                      else
                        value.respond_to?(:dup) && !value.is_a?(Symbol) && !value.is_a?(Numeric) && !value.nil? ? value.dup : value
                      end
          unfrozen[new_key] = new_value
        rescue StandardError
          # If we can't duplicate, just use the original value
          unfrozen[key] = value
        end
        unfrozen
      rescue StandardError
        {}
      end
    end
  end
end
