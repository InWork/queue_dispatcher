class AddResultToTasks < ActiveRecord::Migration
  def up
    add_column "<%= options[:tasks_table_name] %>", :result, :text
  end

  def down
    remove_column "<%= options[:tasks_table_name] %>", :result, :text
  end
end