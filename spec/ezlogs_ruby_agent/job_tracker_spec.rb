# frozen_string_literal: true

# require 'spec_helper'
# require 'ezlogs_ruby_agent/job_tracker'
# require 'ezlogs_ruby_agent/event_queue'

# RSpec.describe EzlogsRubyAgent::JobTracker do
#   class ExampleJob
#     include EzlogsRubyAgent::JobTracker

#     def perform(*args)
#       true
#     end
#   end

#   let(:args) { ['arg1', 'arg2'] }
#   let(:job) { ExampleJob.new }

#   before do
#     allow(EzlogsRubyAgent::EventQueue).to receive(:add)
#   end

#   describe '#perform' do
#     context 'when the job is successful' do
#       it 'adds a completed event to the EventQueue' do
#         allow(Time).to receive(:current).and_return(Time.now)
#         start_time = Time.current

#         job.perform(*args)

#         end_time = Time.current

#         expect(EzlogsRubyAgent::EventQueue).to have_received(:add).with(hash_including({
#           type: "background_job",
#           job_name: "ExampleJob",
#           arguments: args,
#           status: "completed",
#           request_id: "request-id",
#           duration: (end_time - start_time).to_f,
#           timestamp: end_time
#         }))
#       end
#     end

#     context 'when the job fails' do
#       it 'adds a failed event to the EventQueue with error message' do
#         allow(job).to receive(:perform).and_raise(StandardError.new("Job failed"))

#         expect {
#           begin
#             job.perform(*args, options)
#           rescue StandardError
#           end
#         }.to change {
#           EzlogsRubyAgent::EventQueue
#         }.to have_received(:add).with({
#           type: "background_job",
#           job_name: "ExampleJob",
#           arguments: args,
#           status: "failed",
#           request_id: "request-id",
#           error: "Job failed",
#           timestamp: an_instance_of(Time)
#         })
#       end
#     end

#     context 'when request_id is not passed in the options' do
#       it 'uses Thread.current[:ezlogs_request_id] if available' do
#         Thread.current[:ezlogs_request_id] = 'thread-id'

#         allow(Time).to receive(:current).and_return(Time.now)
#         start_time = Time.current

#         job.perform(*args)

#         end_time = Time.current

#         expect(EzlogsRubyAgent::EventQueue).to have_received(:add).with(hash_including({
#           type: "background_job",
#           job_name: "ExampleJob",
#           arguments: args,
#           status: "completed",
#           request_id: "thread-id",
#           duration: (end_time - start_time).to_f,
#           timestamp: end_time
#         }))
#       end
#     end

#     context 'when the job is not trackable' do
#       it 'does not add an event to the EventQueue' do
#         allow_any_instance_of(EzlogsRubyAgent::JobTracker).to receive(:trackable_job?).and_return(false)

#         job.perform(*args)

#         expect(EzlogsRubyAgent::EventQueue).not_to have_received(:add)
#       end
#     end
#   end
# end
