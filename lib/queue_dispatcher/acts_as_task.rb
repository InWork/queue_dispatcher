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
      def acts_as_task(args = {})
        # Include number-helper for number_to_human_size method
        include ActionView::Helpers::NumberHelper

        include QueueDispatcher::ActsAsTask::InstanceMethods
        extend QueueDispatcher::ActsAsTask::SingletonMethods

        @acts_as_task_config = QueueDispatcher::ActsAsTask::Config.new(args[:task_queue_model] || :task_queue)

        belongs_to            acts_as_task_config.task_queue_class_name.to_sym
        has_many              :task_dependencies, :dependent => :destroy, :foreign_key => :task_id
        has_many              :dependent_tasks, :through => :task_dependencies
        has_many              :inverse_task_dependencies, :class_name => 'TaskDependency', :foreign_key => 'dependent_task_id', :dependent => :destroy
        has_many              :inverse_dependent_tasks, :through => :inverse_task_dependencies, :source => :task
        validates_presence_of :target, :method_name, :state
        serialize             :target
        serialize             :args
        serialize             :result

        # Add dynamic associations to task_dependency and task_property according to the class name
        TaskDependency.instance_eval %Q{
          belongs_to :task, :class_name => '#{self.name}'
          belongs_to :dependent_task, :class_name => '#{self.name}'
        }
      end


      [:success, :error].each do |state|
        define_method("on_#{state}") do |*method_names|
          method_names.each do |method_name|
            eval "(@#{state}_callback_chain ||= []) << method_name"
          end
        end
      end
    end


    module SingletonMethods
      def acts_as_task_config
        @acts_as_task_config
      end


      [:success, :error].each do |state|
        define_method("#{state}_callback_chain") do
          eval("@#{state}_callback_chain") || []
        end
      end
    end


    module InstanceMethods
      def acts_as_task_task_queue
        self.send(self.class.acts_as_task_config.task_queue_class_name)
      end


      def payload
        if target.is_a?(QueueDispatcher::TargetContainer)
          target.payload
        else
          target
        end
      end


      # Add task_id to the args
      def args
        a = super
        a[-1] = a.last.merge(task_id: self.id) if a && a.instance_of?(Array) && a.last.instance_of?(Hash)
        a
      end


      # This method updates the task state according to the return code of their corresponding command and removes it from the task_queue
      def update_state_and_exec_callbacks(result, remove_from_queue = false, logger = nil)
        rc = output = error_msg = nil

        if result.methods.map(&:to_sym).include?(:rc) && result.methods.map(&:to_sym).include?(:output) && result.methods.map(&:to_sym).include?(:error_msg)
          rc        = result.rc
          output    = result.output
          error_msg = result.error_msg
          result    = nil
        elsif result.kind_of?(Hash)
          rc        = result[:rc]
          output    = result[:output]
          error_msg = result[:error_msg]
          result    = nil
        end

        output ||= ''
        successful = result.methods.map(&:to_sym).include?(:successful?) ? result.successful? : rc.nil? || rc == 0

        if successful
          self.update_attributes :state         => 'successful',
                                 :perc_finished => 100,
                                 :message       => output.truncate(10256),
                                 :result        => result
          success_callbacks(logger)
        else
          self.update_attributes :state     => 'error',
                                 :error_msg => error_msg,
                                 :message   => output.truncate(10256),
                                 :result    => result
          error_callbacks(logger)
        end

        self.update_attributes :task_queue_id => nil if remove_from_queue


        rc
      end


      # Update the attributes perc_finished and message according to the args
      def update_message(args = {})
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


      # Is the task_queue in state config_reload?
      def reloading_config?
        acts_as_task_task_queue && acts_as_task_task_queue.reloading_config? && acts_as_task_task_queue.tasks.where(state: 'new').first.id == id
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
        attr_str = ''
        Task.attribute_names.each{ |a| attr_str += self.send(a).to_s }
        Digest('MD5').digest(attr_str)
      end


      # Execute task
      def execute!
        payload.task_id = id if payload.methods.include?(:task_id=)
        payload.send(method_name, *args)
      end

    private

      # Callbacks
      [:success, :error].each do |state|
        define_method("#{state}_callbacks") do |logger|
          eval("self.class.#{state}_callback_chain").each do |method_name|
            begin
              send method_name
            rescue => exception
              backtrace = exception.backtrace.join("\n  ")
              msg = "Fatal error in method '#{method_name}', while executing it in #{state}_callbacks: #{$!}\n  #{backtrace}"
              logger.send(:error, msg) if logger
            end
          end
        end
      end

    end
  end
end
