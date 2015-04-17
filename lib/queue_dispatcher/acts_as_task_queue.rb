require 'sys/proctable'
require 'queue_dispatcher/rc_and_msg'

module QueueDispatcher
  module ActsAsTaskQueue
    def self.included(base)
      base.extend(ClassMethods)
    end


    class Config
      attr_reader :task_class_name
      attr_reader :leave_running_tasks_in_queue
      attr_reader :leave_finished_tasks_in_queue
      attr_reader :idle_wait_time
      attr_reader :task_finish_wait_time
      attr_reader :poll_time
      attr_reader :debug

      def initialize(args)
        @task_class_name               = (args[:task_model] || :task).to_s.underscore
        @leave_finished_tasks_in_queue = args[:leave_finished_tasks_in_queue].nil? ? false : args[:leave_finished_tasks_in_queue]
        @leave_running_tasks_in_queue  = args[:leave_running_tasks_in_queue].nil? ? false : args[:leave_running_tasks_in_queue]
        @leave_running_tasks_in_queue  = true if @leave_finished_tasks_in_queue
        @idle_wait_time                = args[:idle_wait_time] || 0
        @task_finish_wait_time         = args[:task_finish_wait_time] || 0
        @poll_time                     = args[:poll_time] || 2.seconds
        @debug                         = args[:debug]
      end
    end


    module ClassMethods
      def acts_as_task_queue(args = {})
        include ActionView::Helpers::UrlHelper
        include QdLogger

        include QueueDispatcher::ActsAsTaskQueue::InstanceMethods
        extend QueueDispatcher::ActsAsTaskQueue::SingletonMethods

        @acts_as_task_queue_config = QueueDispatcher::ActsAsTaskQueue::Config.new(args)

        has_many acts_as_task_queue_config.task_class_name.pluralize.to_sym, -> { order(:priority, :id) }
        serialize :interrupts, Array
      end
    end


    module SingletonMethods
      def acts_as_task_queue_config
        @acts_as_task_queue_config
      end


      # Check if a certain PID is still running and is a ruby process
      def pid_running?(pid)
        ps = pid ? Sys::ProcTable.ps(pid) : nil
        if ps
          # Asume, that if the command of the 'ps'-output is 'ruby', the process is still running
          ps.comm == 'ruby'
        else
          false
        end
      end


      # Check if QueueDispatcher is running.
      def qd_running?
        hb_tqs = TaskQueue.where(state: 'heartbeat')
        running = false
        hb_tqs.each { |tq| running = true if pid_running?(tq.pid) && tq.updated_at > 1.minute.ago }
        running
      end


      # Are there any running task_queues?
      def any_running?
        running = false
        all.each{ |tq| running = true if tq.running? || tq.brand_new? }
        running
      end


      # Get next pending task_queue
      def get_next_pending
        task_queue = nil

        transaction do
          # Find next task_queue which is not running and not in state error
          order(:id).lock(true).all.each { |tq| task_queue = tq unless task_queue || tq.pid_running? || tq.state == 'error' || tq.state == 'heartbeat' }

          # Update pid inside the atomic transaction to be sure, the next call of this method will not give the same queue a second time
          task_queue.update_attribute :pid, $$ if task_queue
        end

        task_queue
      end


      # Find or create a task_queue by its name which is not in state 'error'. Create one, if there does not exists one
      def find_or_create_by_name(name, options = {})
        transaction do
          self.where(:name => name).where("state != 'error'").first || self.create(:name => name, :state => 'new', terminate_immediately: options[:terminate_immediately])
        end
      end


      # Kill all running TaskQueues immediately and destroy them.
      def reset_immediately!
        all.each do |tq|
          tq.update_attributes state: 'aborted'

          # Kill the TaskQueue with SIGKILL
          Process.kill 'KILL', tq.pid if tq.pid_running?

          # Update task_state to aborted and release all its locks
          tq.tasks.each do |task|
            task.update_attributes state: 'aborted' unless task.state == 'successful' || task.state == 'finished'
            tq.send(:release_lock_for, task)
          end
          tq.destroy
        end
      end
    end


    module InstanceMethods
      def acts_as_task_queue_tasks
        self.send(acts_as_task_queue_config.task_class_name.pluralize)
      end


      # Put a new task into the queue
      def push(task)
        acts_as_task_queue_tasks << task
      end


      # Get the next ready to run task out of the queue. Consider the priority and the dependent tasks, which is defined in the association defined on
      # top of this model.
      def pop(args = {})
        task      = nil
        log_debug = acts_as_task_queue_config.debug

        transaction do
          # Find next pending task, where all dependent tasks are executed
          all_tasks = acts_as_task_queue_tasks.lock(true).all
          pos       = 0
          while task.nil? && pos < all_tasks.to_a.count do
            t = all_tasks[pos]
            if t.dependent_tasks_executed?
              task = t if t.state == 'new'
            else
              log :msg => "Task #{t.id}: Waiting for dependent tasks #{t.dependent_tasks.map{|dt| dt.id}.join ','}...", :sev => :debug if log_debug
            end
            pos += 1
          end

          # Remove task from current queue
          if task
            if args[:remove_task].nil? || args[:remove_task]
              task.update_attribute :task_queue_id, nil
            else
              task.update_attribute :state, 'new_popped'
            end
          end
        end

        task
      end


      # Returns the state of this task list (:stopped or :running)
      def task_states
        states = determine_state_of_task_array acts_as_task_queue_tasks

        if states[:empty]
          nil
        elsif states[:running]
          :running
        elsif states[:init_queue]
          :init_queue
        elsif states[:pending]
          :pending
        elsif states[:acquire_lock]
          :acquire_lock
        elsif states[:error]
          :error
        elsif states[:aborted]
          :aborted
        elsif states[:new]
          :new
        elsif states[:successful]
          :successful
        else
          :unknown
        end
      end


      # Return true, if the command of the process with pid 'self.pid' is 'ruby'
      def pid_running?
        self.class.pid_running?(self.pid)
      end


      # Return true, if the task_queue is still running
      def running?
        state == 'running' && pid_running?
      end


      # Return true, if the task_queue is in state new and is not older 30 seconds
      def brand_new?
        state == 'new' && (Time.now - created_at) < 30.seconds
      end


      # Return true if there are no tasks in this taskqueue
      def empty?
        acts_as_task_queue_tasks.empty?
      end


      # Are there any running or pending tasks in the queue?
      def pending_tasks?
        transaction do
          queue = TaskQueue.where(:id => self.id).lock(true).first
          states = determine_state_of_task_array queue.acts_as_task_queue_tasks.lock(true)
          states[:running] || states[:pending] || states[:acquire_lock] || states[:init_queue]
        end
      end


      # Are all tasks executed?
      def all_done?
        ! pending_tasks? || empty?
      end


      # Return true, if the task_queue is working or has pending jobs
      def working?
        self.task_states == :running && self.running?
      end


      # Return true, if the task_queue has pending jobs and is running but no job is running
      def pending?
        ts = task_states
        (ts == :new || ts == :pending || ts == :acquire_lock) && self.running?
      end


      # Return true, if the task_queue is in state 'reloading_config'
      def reloading_config?
        pid_running? && state == 'reloading_config'
      end


      # Kill a task_queue
      def kill
        Process.kill('HUP', pid) if pid
      end


      # Destroy the queue if it has no pending jobs
      def destroy_if_all_done!
        transaction do
          queue = TaskQueue.where(:id => self.id).lock(true).first
          queue.destroy if queue && queue.all_done?
        end
      end


     # Remove finished tasks from queue
     def remove_finished_tasks!
       trasnaction do
         tasks.each{ |t| t.update_attribute(:task_queue_id, nil) if t.executed? }
       end
     end


      # Execute all tasks in the queue
      def run!(args = {})
        task          = nil
        @logger       = args[:logger] || Logger.new("#{File.expand_path(Rails.root)}/log/task_queue.log")
        finish_state  = 'aborted'
        task_queue    = self
        print_log     = args[:print_log]

        task_queue.update_attribute :state, 'running'

        # Set logger in engine
        @engine.logger = @logger if defined? @engine && @engine.methods.include?(:logger=)
        log :msg => "#{name}: Starting TaskQueue #{task_queue.id}...", :print_log => print_log

        # Init. Pop first task from queue, to show init_queue-state
        task = task_queue.pop(:remove_task => false)
        task.update_attribute :state, 'init_queue' if task
        init

        # Put task, which was used for showing the init_queue-state, back into the task_queue
        task.update_attributes :state => 'new', :task_queue_id => task_queue.id if task
        task_queue.reload

        # Ensure, that each task_queue is executed at least once, even if there are no tasks inside at the time it is started (this
        # can happen, if there are a lot of DB activities...)
        first_run = true
        # Loop as long as the task_queue exists with states 'running' and until the task_queue has pending tasks
        while task_queue && task_queue.state == 'running' && (task_queue.pending_tasks? || first_run) do
          first_run = false

          # Pop next task from queue
          task = task_queue.pop(:remove_task => (! acts_as_task_queue_config.leave_running_tasks_in_queue))

          if task
            if task.new?
              # Start
              task.update_attributes :state => 'acquire_lock', :perc_finished => 0
              get_lock_for task
              log :msg => "#{name}: Starting task #{task.id} (#{task.payload.class.name}.#{task.method_name})...", :print_log => print_log
              task.update_attributes :state => 'running'

              # Execute the method defined in task.method
              if task.payload.methods.map(&:to_sym).include?(task.method_name.to_sym)
                if task.dependent_tasks_had_errors
                  error_msg = 'Dependent tasks had errors!'
                  log :msg => error_msg,
                      :sev => :warn, 
                      :print_log => print_log
                  result = QueueDispatcher::RcAndMsg.bad_rc error_msg
                else
                  payload = task.payload
                  payload.logger = @logger if payload.methods.include?(:logger=) || payload.methods.include?('logger=')
                  result = task.execute!
                end
              else
                error_msg = "unknown method '#{task.method_name}' for #{task.payload.class.name}!"
                log :msg => error_msg,
                    :sev => :warn,
                    :print_log => print_log
                result = QueueDispatcher::RcAndMsg.bad_rc error_msg
              end

              # Change task state according to the return code and remove it from the queue
              task.update_state result
              cleanup_locks_after_error_for task
              task.update_attribute :task_queue_id, nil unless acts_as_task_queue_config.leave_finished_tasks_in_queue
              log :msg => "#{name}: Task #{task.id} (#{task.payload.class.name}.#{task.method_name}) finished with state '#{task.state}'.", :print_log => print_log

              # Wait between tasks
              sleep acts_as_task_queue_config.task_finish_wait_time
            end
          else
            # We couldn't fetch a task out of the queue but there should still exists some. Maybe some are waiting for dependent tasks.
            # Sleep some time before trying it again.
            sleep acts_as_task_queue_config.poll_time
          end

          # Interrupts
          handle_interrupts print_log: print_log

          # Reload task_queue to get all updates
          task_queue = TaskQueue.find_by_id task_queue.id

          # If all tasks are finished, a config reload will be executed at the end of this method. To avoid too much config reloads,
          # wait some time before continuing. Maybe, some more tasks will added to the queue?!
          wait_time = 0
          unless task_queue.nil? || task_queue.terminate_immediately
            until task_queue.nil? || task_queue.pending_tasks? || wait_time >= acts_as_task_queue_config.idle_wait_time || task_queue.state != 'running' do
              sleep acts_as_task_queue_config.poll_time
              wait_time += acts_as_task_queue_config.poll_time
              task_queue = TaskQueue.find_by_id task_queue.id
            end
          end

          # Reset logger since this got lost by reloading the task_queue
          task_queue.logger = @logger if task_queue
        end

        # Reload config if last task was not a config reload
        config_reload_required = cleanup_before_auto_reload
        if config_reload_required
          task_queue.update_attributes :state => 'reloading_config' if task_queue
          reload_config task, print_log: print_log
        end

        # Loop has ended
        log :msg => "#{name}: TaskQueue has ended!", :print_log => print_log
        finish_state = 'stopped'
      rescue => exception
        # Error handler
        backtrace = exception.backtrace.join("\n  ")
        log :msg => "Fatal error in method 'run!': #{$!}\n  #{backtrace}", :sev => :error, :print_log => print_log
        puts "Fatal error in method 'run!': #{$!}\n#{backtrace}"
        task.update_state QueueDispatcher::RcAndMsg.bad_rc("Fatal error: #{$!}") if task
        cleanup_locks_after_error_for task if task
        task.update_attributes state: 'error' if task && task.state != 'finished'
      ensure
        # Reload task and task_queue, to ensure the objects are up to date
        task_queue = TaskQueue.find_by_id task_queue.id if task_queue
        task       = Task.find_by_id task.id if task

        # Delete task_queue
        task_queue.destroy_if_all_done! if task_queue

        # Update states of task and task_queue
        task.update_attributes :state => 'aborted' if task && task.state == 'running'
        task_queue.update_attributes :state => finish_state, :pid   => nil if task_queue

        # Clean up
        deinit
      end


      #----------------------------------------------------------------------------------------------------------------
      private
      #----------------------------------------------------------------------------------------------------------------


      def acts_as_task_queue_config
        self.class.acts_as_task_queue_config
      end


      def determine_state_of_task_array(task_array)
        successful = true
        new = true
        pending = false
        error = false
        aborted = false
        running = false
        acquire_lock = false
        init_queue = false

        task_array.each do |task|
          running = true if task.state == 'running'
          acquire_lock = true if task.state == 'acquire_lock'
          successful = false unless task.state == 'finished' || task.state == 'successful'
          new = false unless task.state == 'new' || task.state == 'new_popped' || task.state == 'build'
          pending = true if (task.state == 'new' || task.state == 'new_popped' || task.state == 'build' || task.state == 'pending')
          error = true if task.state == 'error'
          aborted = true if task.state == 'aborted'
          init_queue = true if task.state == 'init_queue'
        end

        {:running      => running,
         :acquire_lock => acquire_lock,
         :successful   => successful,
         :new          => new,
         :pending      => pending,
         :error        => error,
         :aborted      => aborted,
         :empty        => task_array.empty?,
         :init_queu    => init_queue}
      end


      # Get Lock
      def get_lock_for(task)
      end


      # Release Lock
      def release_lock_for(task)
      end


      # Clean up locks after an error occured
      def cleanup_locks_after_error_for(task)
        release_lock_for task
      end


      # Here you can add clean up tasks which will be executed before the auto-reload at the end of the task-queue execution. This is handy
      # if you want to remove the virtual-flag from objects for example. Return true, when a config reload is needed.
      def cleanup_before_auto_reload
        true
      end


      # Initialize
      def init
      end


      # Deinitialize
      def deinit
      end


      # Reload config
      def reload_config(last_task, args = {})
        #log :msg => "#{name}: Reloading config...", :print_log => args[:print_log]
      end


      # Interrupt handler
      def handle_interrupts(args = {})
        interrupts.each { |int| send int.to_sym }
        update_attributes :interrupts => []
      rescue => exception
        backtrace = exception.backtrace.join("\n  ")
        log :msg => "Fatal error in method 'handle_interrupts': #{$!}\n  #{backtrace}", :sev => :error, :print_log => args[:print_log]
      end

    end
  end
end
