require 'spec_helper'

RSpec.describe 'Story Linking Validation', type: :integration do
  before do
    EzlogsRubyAgent.configure do |config|
      config.service_name = 'story-linking-test'
      config.environment = 'test'
      config.included_resources = []
      config.excluded_resources = []
    end

    # Enable debug mode to capture events
    EzlogsRubyAgent.debug_mode = true
    EzlogsRubyAgent.clear_captured_events
  end

  after do
    EzlogsRubyAgent.debug_mode = false
    EzlogsRubyAgent.clear_captured_events
    EzlogsRubyAgent::CorrelationManager.clear_context
  end

  describe 'Hierarchical Correlation Context' do
    it 'maintains primary correlation ID across HTTP -> Database -> Job chain' do
      # 1. Start with HTTP request context
      http_context = EzlogsRubyAgent::CorrelationManager.start_request_context(
        'req_story_123',
        'sess_user_456',
        { user_id: 124_142 }
      )

      primary_correlation_id = http_context.primary_correlation_id

      # Simulate HTTP request event
      http_event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'http.request',
        action: 'POST /graphql',
        actor: { type: 'user', id: 124_142, email: '[REDACTED]' },
        subject: { type: 'graphql', id: 'OverrideEquipmentItemStatus' }
      )
      EzlogsRubyAgent.writer.log(http_event)

      # 2. Create child context for database operation
      database_context = EzlogsRubyAgent::CorrelationManager.create_child_context(
        component: 'database',
        operation: 'update'
      )

      # Simulate database change event
      database_event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'data.change',
        action: 'smart_portal_equipment_item.update',
        actor: { type: 'user', id: 124_142, email: '[REDACTED]' },
        subject: { type: 'smart_portal_equipment_item', id: 'fe56e1b7-b63f-4a1f-9e2f-331419581e05' }
      )
      EzlogsRubyAgent.writer.log(database_event)

      # 3. Extract correlation data and simulate job enqueue
      correlation_data = EzlogsRubyAgent::CorrelationManager.extract_correlation_data

      # 4. Create job context in a separate thread (simulating background job)
      job_events = []
      Thread.new do
        job_context = EzlogsRubyAgent::CorrelationManager.inherit_context(
          correlation_data,
          component: 'job',
          metadata: { job_class: 'SmartPortal::LogCompanyEventJob' }
        )

        # Simulate job execution event
        job_event = EzlogsRubyAgent::UniversalEvent.new(
          event_type: 'job.execution',
          action: 'SmartPortal::LogCompanyEventJob.completed',
          actor: { type: 'user', id: 124_142, email: '[REDACTED]' },
          subject: { type: 'job', id: '7af69a783c763b7ac0085232' }
        )
        EzlogsRubyAgent.writer.log(job_event)

        # Second database operation within job
        EzlogsRubyAgent::CorrelationManager.create_child_context(
          component: 'database',
          operation: 'create'
        )

        event_creation_event = EzlogsRubyAgent::UniversalEvent.new(
          event_type: 'data.change',
          action: 'smart_portal_company_event_equipment_item_status_overridden.create',
          actor: { type: 'user', id: 124_142, email: '[REDACTED]' },
          subject: { type: 'smart_portal_company_event_equipment_item_status_overridden',
                     id: '6b00384c-7e71-4a15-92bc-9cefcecb352a' }
        )
        EzlogsRubyAgent.writer.log(event_creation_event)

        job_events << job_event
        job_events << event_creation_event
      end.join

      # Validate correlation hierarchy
      all_events = EzlogsRubyAgent.captured_events
      expect(all_events.size).to eq(4)

      # All events should have the same primary_correlation_id
      primary_ids = all_events.map { |e| e[:event][:correlation][:primary_correlation_id] }.uniq
      expect(primary_ids.size).to eq(1)
      expect(primary_ids.first).to eq(primary_correlation_id)

      # Events should have different correlation_ids but share primary
      correlation_ids = all_events.map { |e| e[:event][:correlation][:correlation_id] }.uniq
      expect(correlation_ids.size).to be > 1

      # Verify component chain progression
      http_event_captured = all_events.find { |e| e[:event][:event_type] == 'http.request' }
      expect(http_event_captured[:event][:correlation][:chain]).to eq(['web'])
      expect(http_event_captured[:event][:correlation][:depth]).to eq(0)

      database_event_captured = all_events.find { |e| e[:event][:action] == 'smart_portal_equipment_item.update' }
      expect(database_event_captured[:event][:correlation][:chain]).to include('web', 'database')
      expect(database_event_captured[:event][:correlation][:depth]).to eq(1)

      job_event_captured = all_events.find { |e| e[:event][:event_type] == 'job.execution' }
      expect(job_event_captured[:event][:correlation][:chain]).to include('web', 'job')
      expect(job_event_captured[:event][:correlation][:depth]).to eq(2)

      final_db_event = all_events.find do |e|
        e[:event][:action] == 'smart_portal_company_event_equipment_item_status_overridden.create'
      end
      expect(final_db_event[:event][:correlation][:chain]).to include('web', 'job', 'database')
      expect(final_db_event[:event][:correlation][:depth]).to eq(3)
    end

    it 'supports story reconstruction by primary correlation ID' do
      # Start a correlation context
      context = EzlogsRubyAgent::CorrelationManager.start_request_context('req_story_789')
      primary_id = context.primary_correlation_id

      # Create multiple child contexts with different components
      contexts = []

      # Database context
      db_context = EzlogsRubyAgent::CorrelationManager.create_child_context(
        component: 'database',
        operation: 'create'
      )
      contexts << db_context

      # Job context
      job_context = EzlogsRubyAgent::CorrelationManager.inherit_context(
        context.to_h,
        component: 'job'
      )
      contexts << job_context

      # All contexts should share the same primary correlation ID
      contexts.each do |ctx|
        expect(ctx.primary_correlation_id).to eq(primary_id)
        expect(ctx.correlation_id).not_to eq(primary_id) # Should have unique correlation_id
      end

      # Test story reconstruction
      story = EzlogsRubyAgent::CorrelationManager::StoryReconstructor.find_complete_story(
        job_context.correlation_id
      )

      expect(story[:primary_correlation_id]).to eq(primary_id)
      expect(story[:story_reconstruction_enabled]).to be true
    end

    it 'handles job inheritance correctly' do
      # Start parent context
      parent_context = EzlogsRubyAgent::CorrelationManager.start_flow_context(
        'equipment_override',
        'fe56e1b7-b63f-4a1f-9e2f-331419581e05'
      )
      correlation_data = EzlogsRubyAgent::CorrelationManager.extract_correlation_data

      # Simulate job inheritance in separate thread
      inherited_context = nil
      Thread.new do
        inherited_context = EzlogsRubyAgent::CorrelationManager.inherit_context(
          correlation_data,
          component: 'job',
          metadata: { job_class: 'TestJob' }
        )
      end.join

      # Verify inheritance
      expect(inherited_context.primary_correlation_id).to eq(parent_context.primary_correlation_id)
      expect(inherited_context.correlation_id).not_to eq(parent_context.correlation_id)
      expect(inherited_context.chain).to include('equipment_override', 'job')
      expect(inherited_context.depth).to eq(parent_context.depth + 1)
      expect(inherited_context.parent_flow_id).to eq(parent_context.flow_id)
      expect(inherited_context.metadata[:inherited_from]).to eq(parent_context.correlation_id)
    end

    it 'preserves correlation context across complex nested operations' do
      # Start with HTTP request
      EzlogsRubyAgent::CorrelationManager.start_request_context('req_complex')
      root_context = EzlogsRubyAgent::CorrelationManager.current_context

      # Multiple nested operations
      depth_1_context = EzlogsRubyAgent::CorrelationManager.create_child_context(
        component: 'service',
        operation: 'process'
      )

      depth_2_context = EzlogsRubyAgent::CorrelationManager.create_child_context(
        component: 'database',
        operation: 'transaction'
      )

      depth_3_context = EzlogsRubyAgent::CorrelationManager.create_child_context(
        component: 'job',
        operation: 'background'
      )

      # All should maintain the same primary correlation ID
      primary_id = root_context.primary_correlation_id

      [depth_1_context, depth_2_context, depth_3_context].each_with_index do |ctx, index|
        expect(ctx.primary_correlation_id).to eq(primary_id)
        expect(ctx.depth).to eq(index + 1)
        expect(ctx.chain.size).to eq(index + 2) # web + additional components
      end

      # Chain should show progression
      expect(depth_3_context.chain).to eq(%w[web service database job])
    end
  end

  describe 'Backward Compatibility' do
    it 'maintains compatibility with existing correlation_id usage' do
      # Old style context creation
      EzlogsRubyAgent::CorrelationManager.start_request_context('req_compat')
      context = EzlogsRubyAgent::CorrelationManager.current_context

      # Should still have correlation_id field
      expect(context.correlation_id).to be_present
      expect(context.correlation_id).to start_with('corr_')

      # Primary should default to correlation_id when not explicitly set
      expect(context.primary_correlation_id).to eq(context.correlation_id)

      # Event creation should work normally
      event = EzlogsRubyAgent::UniversalEvent.new(
        event_type: 'test.event',
        action: 'compatibility_test',
        actor: { type: 'test', id: '1' }
      )

      expect(event.correlation[:correlation_id]).to be_present
      expect(event.correlation[:primary_correlation_id]).to be_present
    end
  end
end
