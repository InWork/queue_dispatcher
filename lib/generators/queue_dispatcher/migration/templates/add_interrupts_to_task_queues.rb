class AddInterruptsToTaskQueues < ActiveRecord::Migration
  def up
    add_column "<%= options[:task_queues_table_name] %>", :interrupts, :text
  end

  def down
    remove_column "<%= options[:task_queues_table_name] %>", :interrupts, :string
  end
end