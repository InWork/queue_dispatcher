module QueueDispatcher
  module ActsAsTask
    def self.included(base)
      base.extend(ClassMethods)
    end


    class Config
      attr_reader :task_queue_class_name

      def initialize(task_queue_class_name)
        @task_queue_class_name = task_queue_class_name.to_s.underscore
      end
    end


    module ClassMethods
      def acts_as_task args = {}
        # Include number-helper for number_to_human_size method
        include ActionView::Helpers::NumberHelper

        include QueueDispatcher::ActsAsTask::InstanceMethods
        extend QueueDispatcher::ActsAsTask::SingletonMethods

        @acts_as_task_config = QueueDispatcher::ActsAsTask::Config.new(args[:task_queue_model] || :task_queue)

        belongs_to            acts_as_task_config.task_queue_class_name
        has_many              :task_dependencies, :dependent => :destroy, :foreign_key => :task_id
        has_many              :dependent_tasks, :through => :task_dependencies
        has_many              :inverse_task_dependencies, :class_name => 'TaskDependency', :foreign_key => 'dependent_task_id', :dependent => :destroy
        has_many              :inverse_dependent_tasks, :through => :inverse_task_dependencies, :source => :task
        validates_presence_of :target, :method_name, :state
        serialize             :target
        serialize             :args

        # Add dynamic associations to task_dependency and task_property according to the class name
        TaskDependency.instance_eval %Q{
          belongs_to :task, :class_name => '#{self.name}'
          belongs_to :dependent_task, :class_name => '#{self.name}'
        }
      end
    end


    module SingletonMethods
      def acts_as_task_config
        @acts_as_task_config
      end
    end


    module InstanceMethods
      def acts_as_task_task_queue
        self.send(self.class.acts_as_task_config.task_queue_class_name)
      end


      # Add task_id to the args
      def args
        a = super
        a[-1] = a.last.merge(task_id: self.id) if a && a.instance_of?(Array) && a.last.instance_of?(Hash)
        a
      end


      # This method updates the task state according to the return code of their corresponding command
      def update_state(rc_and_msg)
        rc = output = error_msg = nil

        if rc_and_msg.is_a?(QueueDispatcher::RcAndMsg)
          rc = rc_and_msg.rc
          output = rc_and_msg.output
          error_msg = rc_and_msg.error_msg
        elsif rc_and_msg.kind_of?(Hash)
          rc = rc_and_msg[:rc]
          output = rc_and_msg[:output]
          error_msg = rc_and_msg[:error_msg]
        end

        output ||= ""

        if rc.nil? || rc == 0
          self.update_attributes :state => "successful",
                                 :perc_finished => 100,
                                 :message => output.truncate(10256)
        else
          self.update_attributes :state => "error",
                                 :error_msg => error_msg,
                                 :message => output.truncate(10256)
        end
      end


      # Update the attributes perc_finished and message according to the args
      def update_message args = {}
        msg = args[:msg]
        perc_finished = args[:perc_finished]

        self.update_attribute :message, msg if msg
        self.update_attribute :perc_finished, perc_finished if perc_finished
      end


      # Is this task new?
      def new?
         state == 'new' || state == 'new_popped'
      end


      # Is this task pending?
      def pending?
        acts_as_task_task_queue && state == 'new'
      end


      # Is this task pending?
      def acquire_lock?
        acts_as_task_task_queue && acts_as_task_task_queue.running? && state == 'acquire_lock'
      end


      # Is this task running?
      def running?
        acts_as_task_task_queue && acts_as_task_task_queue.running? && state == 'running'
      end


      # Was this task finsihed successful?
      def successful?
        state == 'successful' || state == 'finished'
      end


      # Had this task error(s)?
      def error?
        state == 'error' || state.blank?
      end


      # Was this task aborted?
      def aborted?
        state == 'aborted'
      end


      # Is this task waiting until the queue is initialized?
      def init_queue?
        state == 'init_queue'
      end


      # Was this task already executed?
      def executed?
        successful? || error? || aborted?
      end


      # Are all dependent_tasks executed?
      def dependent_tasks_executed?
        state = true
        dependent_tasks.each{ |dt| state = false unless dt.executed? }
        state
      end


      # Check recursive, if one or more of the tasks, which this task is dependent on had errors
      def dependent_tasks_had_errors
        error = false
        dependent_tasks.each do |t|
          error = true if t.state == 'error' || t.dependent_tasks_had_errors
        end
        error
      end


      # Placeholder. Please override it in your model.
      def prosa
      end


      # Calculate md5-Checksum
      def md5
        attr_str = ""
        Task.attribute_names.each{ |a| attr_str += self.send(a).to_s }
        Digest('MD5').digest(attr_str)
      end


      # Execute task
      def execute!
        target.send(method_name, *args)
      end

    end
  end
end
