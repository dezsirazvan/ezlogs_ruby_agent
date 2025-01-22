# frozen_string_literal: true

module EzlogsRubyAgent
  module Jobs
    class EventSenderJob
      if defined?(Sidekiq)
        include Sidekiq::Job

        sidekiq_options queue: EzlogsRubyAgent.config.background_jobs_queue
      else
        include ActiveJob::Base

        queue_as { EzlogsRubyAgent.config.background_jobs_queue }
      end

      def perform(events)
        uri = URI(EzlogsRubyAgent.config.endpoint_url)

        response = Net::HTTP.post(uri, events, 'Content-Type' => 'application/json')

        if response.code.to_i < 200 || response.code.to_i >= 400
          Rails.logger.error("Ezlogs EventSenderJob: Failed to send events: #{response.code} - #{response.body}")
          raise StandardError, 'Failed to send events to Ezlogs'
        end
      rescue StandardError => e
        Rails.logger.error("Ezlogs EventSenderJob: #{e.message}")
        raise e
      end
    end
  end
end
