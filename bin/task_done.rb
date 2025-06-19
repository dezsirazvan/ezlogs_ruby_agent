# !/usr/bin/env ruby

require 'fileutils'
require 'date'

# Check if we have an active task
active_tasks = Dir.glob('ai_tasks/active/*')
if active_tasks.empty?
  puts '❌ No active tasks found!'
  exit 1
end

if active_tasks.length > 1
  puts '⚠️  Multiple active tasks found:'
  active_tasks.each_with_index do |task, index|
    task_name = File.basename(task)
    puts "  #{index + 1}. #{task_name}"
  end

  print "Which task to complete? (1-#{active_tasks.length}): "
  choice = gets.chomp.to_i

  if choice < 1 || choice > active_tasks.length
    puts '❌ Invalid choice!'
    exit 1
  end

  task_to_complete = active_tasks[choice - 1]
else
  task_to_complete = active_tasks.first
end

task_name = File.basename(task_to_complete)
timestamp = Time.now.strftime('%Y-%m-%d')

# Create done directory if it doesn't exist
FileUtils.mkdir_p('ai_tasks/done')

# Add completion info
completion_info = "\n\n---\n\n## ✅ Task Completed\n\n"
completion_info += "**Completed**: #{timestamp}\n"
completion_info += "**Duration**: [Add duration here]\n"
completion_info += "**Key Changes**: [Add summary of changes]\n"
completion_info += "**Next Steps**: [Add any follow-up tasks]\n"

# Add completion info to Feature.md
feature_file = "#{task_to_complete}/Feature.md"
File.open(feature_file, 'a') { |f| f.write(completion_info) } if File.exist?(feature_file)

# Move task to done
destination = "ai_tasks/done/#{task_name}"
FileUtils.mv(task_to_complete, destination)

puts "✅ Task completed and moved to: #{destination}"
puts '🚀 Ready for next task!'
puts ''
puts '📊 Summary:'
puts "  📁 Task: #{task_name}"
puts "  📅 Completed: #{timestamp}"
puts "  📍 Location: #{destination}"
puts ''
puts '🎯 Create next task with: bin/new_task <task-name>'
