class CreateTaskQueues < ActiveRecord::Migration
  def self.up
    create_table "<%= options[:task_queues_table_name] %>" do |t|
      t.string :name
      t.string :state
      t.integer :pid
      t.boolean :terminate_immediately

      t.timestamps
    end

    add_index "<%= options[:task_queues_table_name] %>", :name
  end

  def self.down
    drop_table "<%= options[:task_queues_table_name] %>"
  end
end
