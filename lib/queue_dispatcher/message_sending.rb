require 'active_support/basic_object'

module QueueDispatcher
  class QueueDispatcherProxy < ActiveSupport::BasicObject
    def initialize(target, options = {})
      @target = target
      @options = options
    end

    def method_missing(method, *args)
      # Find or create the task_queue
      terminate_immediately = @options.delete(:terminate_immediately)
      terminate_immediately = terminate_immediately.nil? ? false : terminate_immediately
      terminate_immediately = @options[:queue].nil? ? true : terminate_immediately
      task_queue_name = @options.delete(:queue) || "#{@target.to_s}_#{::Time.now.to_f}"
      task_queue = ::TaskQueue.find_or_create_by_name task_queue_name, terminate_immediately: terminate_immediately

      # Create Task
      default_values   = {priority: 100}
      mandatory_values = {target: @target, method_name: method, args: args, state: 'new', task_queue_id: task_queue.id}
      ::Task.create default_values.merge(@options).merge(mandatory_values)
    end
  end


  module MessageSending
    def enqueue(options = {})
      QueueDispatcherProxy.new(self, options)
    end
  end
end
