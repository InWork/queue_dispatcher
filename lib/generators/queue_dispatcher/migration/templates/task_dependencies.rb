class CreateTaskDependencies < ActiveRecord::Migration
  def self.up
    create_table "<%= options[:task_dependencies_table_name] %>" do |t|
      t.integer :task_id
      t.integer :dependent_task_id

      t.timestamps
    end
    add_index "<%= options[:task_dependencies_table_name] %>", :task_id
    add_index "<%= options[:task_dependencies_table_name] %>", :dependent_task_id
  end

  def self.down
    drop_table "<%= options[:task_dependencies_table_name] %>"
  end
end
