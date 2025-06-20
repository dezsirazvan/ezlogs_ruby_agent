# frozen_string_literal: true

# Mock job system for testing without ActiveJob dependencies
module MockJobSystem
  class Base
    include EzlogsRubyAgent::JobTracker

    # Ensure perform is defined so JobTracker can alias it
    unless method_defined?(:perform)
      def perform(*args, **kwargs)
        perform_job(*args, **kwargs)
      end
    end

    def self.perform_later(*args, **kwargs)
      if args.length == 1 && args.first.is_a?(Hash) && kwargs.empty?
        new.perform(**args.first)
      elsif args.empty? && !kwargs.empty?
        new.perform(**kwargs)
      else
        raise ArgumentError, "Invalid arguments for perform_later: \#{args}, \#{kwargs}"
      end
    end

    def perform_job(**_kwargs)
      # Override in subclasses
      raise NotImplementedError, 'Subclasses must implement perform_job'
    end
  end
end

# Background job for processing orders
class ProcessOrderJob < MockJobSystem::Base
  def perform_job(order_id:, user_id:, **_options)
    # Simulate job processing
    sleep(0.001) # Simulate work

    # Simulate order processing logic
    order = find_order(order_id)

    # For testing failure scenarios, check if this is a failure test
    if order_id.to_s.include?('failure_test') || user_id.to_s.include?('failure_test')
      raise "Order not found: #{order_id}"
    end

    raise "Order not found: #{order_id}" unless order

    # Update order status
    order.update(status: 'processing')

    # Simulate additional processing
    process_payment(order)
    send_notifications(order)

    # Final status update
    order.update(status: 'completed')

    { success: true, order_id: order_id }
  end

  private

  def find_order(order_id)
    # In a real app, this would query the database
    # For testing, use the shared store
    TestRailsApp::Order.find(order_id)
  end

  def process_payment(order)
    # Simulate payment processing
    sleep(0.001)
    order.update(payment_status: 'paid')

    # Log payment event
    EzlogsRubyAgent.log_event(
      event_type: 'payment.processed',
      action: 'payment.success',
      actor: { type: 'system', id: 'payment_processor' },
      subject: { type: 'order', id: order.id },
      metadata: {
        amount: order.total,
        method: 'credit_card',
        transaction_id: "txn_#{SecureRandom.hex(8)}"
      }
    )
  end

  def send_notifications(order)
    # Simulate sending notifications
    sleep(0.001)
    order.update(notification_sent: true)

    # Log notification event
    EzlogsRubyAgent.log_event(
      event_type: 'notification.sent',
      action: 'email.order_confirmation',
      actor: { type: 'system', id: 'notification_service' },
      subject: { type: 'order', id: order.id },
      metadata: {
        type: 'email',
        template: 'order_confirmation',
        recipient: order.user_id
      }
    )
  end

  # Override job metadata for testing
  def job_metadata
    {
      queue_name: 'default',
      job_class: 'ProcessOrderJob',
      retry_count: 0,
      priority: 'normal'
    }
  end

  def job_name
    'ProcessOrderJob'
  end

  def job_id
    "job_#{SecureRandom.hex(8)}"
  end

  def queue_name
    'default'
  end

  def trackable_job?
    true
  end
end

# Job for sending welcome emails
class WelcomeEmailJob < MockJobSystem::Base
  def perform_job(user_id:)
    # Simulate email sending
    sleep(0.001)

    # Log email event
    EzlogsRubyAgent.log_event(
      event_type: 'email.sent',
      action: 'welcome_email.delivered',
      actor: { type: 'system', id: 'email_service' },
      subject: { type: 'user', id: user_id },
      metadata: {
        template: 'welcome',
        status: 'delivered'
      }
    )

    { success: true, user_id: user_id }
  end

  def job_name
    'WelcomeEmailJob'
  end

  def job_id
    "job_#{SecureRandom.hex(8)}"
  end

  def queue_name
    'mailers'
  end

  def trackable_job?
    true
  end
end

# Mock Sidekiq job for testing
if defined?(Sidekiq)
  class SidekiqOrderJob
    include Sidekiq::Worker
    sidekiq_options queue: 'default'

    def perform(order_id:, user_id:)
      # Simulate Sidekiq job processing
      sleep(0.001)
      order = TestRailsApp::Order.find(order_id)
      raise "Order not found: #{order_id}" unless order

      order.update(status: 'sidekiq_processed')
    end
  end
else
  # Fallback for test environments without Sidekiq
  class SidekiqOrderJob
    def self.perform_async(order_id:, user_id:)
      # No-op or log for test
      order = TestRailsApp::Order.find(order_id)
      order.update(status: 'sidekiq_processed') if order
    end
  end
end
