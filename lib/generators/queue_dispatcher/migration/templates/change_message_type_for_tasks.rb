class ChangeMessageTypeForTasks < ActiveRecord::Migration
  def up
    change_column "<%= options[:tasks_table_name] %>", :message, :text
  end

  def down
    change_column "<%= options[:tasks_table_name] %>", :message, :string
  end
end