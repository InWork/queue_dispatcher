class CreateTasks < ActiveRecord::Migration
  def self.up
    create_table "<%= options[:tasks_table_name] %>" do |t|
      t.text :target
      t.string :method_name
      t.text :args
      t.string :state
      t.integer :priority
      t.string :message
      t.integer :perc_finished
      t.string :remark
      t.text :output
      t.text :error_msg
      t.integer :task_queue_id
  
      t.timestamps
    end

    add_index "<%= options[:tasks_table_name] %>", :task_queue_id
  end

  def self.down
    drop_table "<%= options[:tasks_table_name] %>"
  end
end
