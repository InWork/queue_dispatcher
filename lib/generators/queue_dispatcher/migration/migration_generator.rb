require 'rails/generators'
require 'rails/generators/migration'

module QueueDispatcher
  class MigrationGenerator < Rails::Generators::Base
    desc "The queue_dispatcher migration generator creates a database migration for the task_queue model."
    include Rails::Generators::Migration
    source_root File.join(File.dirname(__FILE__), 'templates')

    class_option :task_queues_table_name,
      :type => :string,
      :desc => "Name for the TaskQueue Table",
      :required => false,
      :default => "task_queues"

    class_option :tasks_table_name,
      :type => :string,
      :desc => "Name for the Task Table",
      :required => false,
      :default => "tasks"

    class_option :task_dependencies_table_name,
      :type => :string,
      :desc => "Name for the Task Dependency Table",
      :required => false,
      :default => "task_dependencies"

    def initialize(args = [], options = {}, config = {})
      super
    end

    #attr_reader :lock_table_name

    # Implement the required interface for Rails::Generators::Migration.
    # taken from http://github.com/rails/rails/blob/master/activerecord/lib/generators/active_record.rb
    def self.next_migration_number(dirname)
      if ActiveRecord::Base.timestamped_migrations
        [Time.now.utc.strftime("%Y%m%d%H%M%S"), "%.14d" % (current_migration_number(dirname) + 1)].max
      else
        "%.3d" % (current_migration_number(dirname) + 1)
      end
    end

    def create_migration_file
      migration_template 'task_queues.rb', 'db/migrate/create_task_queues.rb'
      migration_template 'task_dependencies.rb', 'db/migrate/create_task_dependencies.rb'
      migration_template 'change_message_type_for_tasks.rb', 'db/migrate/change_message_type_for_tasks.rb'
      migration_template 'add_interrupts_to_tasks_queues.rb', 'db/migrate/add_interrupts_to_tasks_queues.rb'
      migration_template 'add_result_to_tasks.rb', 'db/migrate/add_result_to_tasks.rb'
    end

  end
end
