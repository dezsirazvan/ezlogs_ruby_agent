# frozen_string_literal: true

require 'rack'
require 'json'
require 'active_support/core_ext/string/inflections'
require 'active_support/json'
require 'active_support/core_ext/object/json'

# Minimal Rails app for integration testing
module TestRailsApp
  # Mock ActiveRecord-like model
  class Order
    attr_accessor :id, :user_id, :total, :status, :created_at, :updated_at, :payment_status, :notification_sent

    # Use class variable for proper sharing across contexts
    @@orders = {}

    class << self
      def find(id)
        @@orders[id]
      end

      def clear_store
        @@orders.clear
      end

      def store_size
        @@orders.size
      end

      def all_orders
        @@orders.values
      end

      def store_order(order)
        @@orders[order.id] = order
      end
    end

    def initialize(attributes = {})
      @id = if attributes[:_force_failure]
              "failure_test_#{SecureRandom.uuid}" # Force job failure
            else
              attributes[:id] || SecureRandom.uuid
            end
      @user_id = attributes[:user_id] || 'anonymous'
      @total = attributes[:total]&.to_f || 0.0
      @status = attributes[:status] || 'pending'
      @payment_status = attributes[:payment_status] || 'pending'
      @notification_sent = attributes[:notification_sent] || false
      @created_at = Time.now
      @updated_at = Time.now
      @changes = {}
      @saved_changes = {}
      @previous_changes = {}
      @is_new_record = true

      # Store in class variable
      @@orders[@id] = self

      # Log order creation event
      log_data_change_event('create')
    end

    def save
      @updated_at = Time.now
      @@orders[@id] = self
      self
    end

    def update(attributes = {})
      attributes.each do |key, value|
        send("#{key}=", value) if respond_to?("#{key}=")
      end
      @updated_at = Time.now

      # Log order update event
      log_data_change_event('update', attributes)

      self
    end

    def attributes
      {
        id: @id,
        user_id: @user_id,
        total: @total,
        status: @status,
        created_at: @created_at,
        updated_at: @updated_at,
        payment_status: @payment_status,
        notification_sent: @notification_sent
      }
    end

    attr_reader :saved_changes, :previous_changes

    def saved_attributes
      attributes
    end

    def attributes_was
      attributes
    end

    def model_name
      OpenStruct.new(singular: 'order')
    end

    def table_name
      'orders'
    end

    def errors
      OpenStruct.new(full_messages: [])
    end

    private

    def trackable_resource?
      true
    end

    def log_data_change_event(action, changes = {})
      EzlogsRubyAgent.log_event(
        event_type: 'data.change',
        action: "order.#{action}",
        actor: { type: 'system', id: 'system' },
        subject: { type: 'order', id: @id },
        metadata: {
          model: 'Order',
          table: 'orders',
          record_id: @id,
          action: action,
          changes: changes,
          user_id: @user_id
        }
      )
    end
  end

  # Mock controller for handling orders
  class OrdersController
    def initialize
      @orders = []
    end

    def create(params)
      # Extract user context from request
      user_id = params[:user_id] || 'anonymous'

      # Create order with proper attributes
      order = Order.new(
        user_id: user_id,
        total: params[:total]&.to_f || 0.0,
        status: 'pending'
      )

      # Save the order (this will trigger the create event)
      if order.save
        # Store the order in the shared store
        Order.store_order(order)

        # Enqueue background job for processing
        # Note: In a real Rails app, this would be done via ActiveJob
        # For testing, we'll enqueue it directly
        enqueue_order_processing(order)

        # Return success response
        {
          status: 201,
          headers: { 'Content-Type' => 'application/json' },
          body: [order.attributes.to_json]
        }
      else
        # Return error response
        {
          status: 422,
          headers: { 'Content-Type' => 'application/json' },
          body: [{ errors: order.errors.full_messages }.to_json]
        }
      end
    end

    def show(id)
      order = @orders.find { |o| o.id == id }

      if order
        {
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: [order.attributes.to_json]
        }
      else
        {
          status: 404,
          headers: { 'Content-Type' => 'application/json' },
          body: [{ error: 'Order not found' }.to_json]
        }
      end
    end

    private

    def enqueue_order_processing(order)
      # Extract current correlation context
      correlation_data = EzlogsRubyAgent::CorrelationManager.extract_correlation_data

      order_args = {
        order_id: order.id,
        user_id: order.user_id,
        _correlation_data: correlation_data
      }
      ProcessOrderJob.perform_later(**order_args)
    end
  end

  # Rack application for handling HTTP requests
  class App
    def initialize
      @controller = OrdersController.new
    end

    def call(env)
      method = env['REQUEST_METHOD']
      path = env['PATH_INFO']
      start_time = Time.now

      # Log HTTP request start
      begin
        response = case [method, path]
                   when ['POST', '/orders']
                     handle_create_order(env)
                   when ['GET', %r{^/orders/(.+)$}]
                     order_id = ::Regexp.last_match(1)
                     handle_show_order(env, order_id)
                   else
                     [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
                   end

        # Log successful HTTP request using the HttpTracker method
        end_time = Time.now
        track_http_request(env, response[0], response[1], end_time - start_time)

        response
      rescue StandardError => e
        # Log failed HTTP request
        end_time = Time.now
        track_http_request(env, 500, { 'Content-Type' => 'application/json' }, end_time - start_time, e)

        [500, { 'Content-Type' => 'application/json' }, [{ error: e.message }.to_json]]
      end
    end

    private

    def track_http_request(env, status, headers, duration, error = nil)
      # Extract request details
      method = env['REQUEST_METHOD']
      path = env['PATH_INFO']
      user_agent = env['HTTP_USER_AGENT'] || 'TestApp/1.0'
      content_type = env['CONTENT_TYPE']

      # Create HTTP request event with proper correlation
      EzlogsRubyAgent.log_event(
        event_type: 'http.request',
        action: method,
        actor: { type: 'system', id: 'system' },
        subject: { type: 'endpoint', id: path },
        metadata: {
          method: method,
          path: path,
          status_code: status,
          duration_ms: (duration * 1000).round(2),
          user_agent: user_agent,
          content_type: content_type,
          error: error&.message
        }
      )
    end

    def handle_create_order(env)
      # Parse request body
      body = parse_request_body(env)

      # Extract user context from headers
      user_context = extract_user_from_headers(env)

      # Merge user context with body params
      params = body.merge(user_context)

      # Call controller
      result = @controller.create(params)

      # Ensure we return a proper Rack response
      if result.is_a?(Hash) && result[:status]
        [result[:status], result[:headers] || {}, result[:body] || []]
      else
        puts "[TestRailsApp::App] Invalid controller response: #{result.inspect}"
        [500, { 'Content-Type' => 'application/json' }, [{ error: 'Invalid response from controller' }.to_json]]
      end
    rescue StandardError => e
      puts "[TestRailsApp::App] Error in handle_create_order: #{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
      [500, { 'Content-Type' => 'application/json' }, [{ error: e.message }.to_json]]
    end

    def handle_show_order(env, order_id)
      result = @controller.show(order_id)

      # Ensure we return a proper Rack response
      if result.is_a?(Hash) && result[:status]
        [result[:status], result[:headers] || {}, result[:body] || []]
      else
        [500, { 'Content-Type' => 'application/json' }, [{ error: 'Invalid response from controller' }.to_json]]
      end
    end

    def parse_request_body(env)
      return {} unless env['rack.input']

      body = env['rack.input'].read
      return {} if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError => e
      puts "[TestRailsApp::App] JSON parse error: #{e.message}"
      {}
    end

    def extract_user_from_headers(env)
      user_id = env['HTTP_X_USER_ID'] ||
                env['HTTP_AUTHORIZATION']&.gsub('Bearer ', '') ||
                'anonymous'

      { user_id: user_id }
    end

    def extract_request_headers(env)
      {
        'User-Agent' => env['HTTP_USER_AGENT'],
        'Accept' => env['HTTP_ACCEPT'],
        'Content-Type' => env['CONTENT_TYPE'],
        'X-User-ID' => env['HTTP_X_USER_ID']
      }.compact
    end
  end
end
