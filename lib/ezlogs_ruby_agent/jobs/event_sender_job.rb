# frozen_string_literal: true

module EzlogsRubyAgent
  module Jobs
    class EventSenderJob < ActiveJob::Base
      queue_as :default

      def perform(events)
        uri = URI(EzlogsRubyAgent.config.endpoint_url)

        response = Net::HTTP.post(uri, events, 'Content-Type' => 'application/json')

        unless response.is_a?(Net::HTTPSuccess)
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
