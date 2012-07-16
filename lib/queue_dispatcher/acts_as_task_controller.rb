module QueueDispatcher
  module ActsAsTaskController
    def self.included(base)
      base.extend(ClassMethods)
    end


    class Config
      attr_reader :task_class_name

      def initialize(task_class_name)
        @task_class_name = task_class_name.to_s.underscore
      end
    end


    module ClassMethods
      def acts_as_task_controller args = {}
        include QueueDispatcher::ActsAsTaskController::InstanceMethods
        extend QueueDispatcher::ActsAsTaskController::SingletonMethods
        @acts_as_task_controller_config = QueueDispatcher::ActsAsTaskController::Config.new(args[:task_model] || :task)
      end
    end


    module SingletonMethods
      def acts_as_task_controller_config
        @acts_as_task_controller_config
      end
    end


    module InstanceMethods
      def my_events
        # Remember the selected page, if the AJAX-Request wants to update the current page
        page = session[:my_events_page] = params[:page] if params[:page] || ! request.xhr?
        page = session[:my_events_page] if page.nil? && request.xhr?
        @tasks = current_user.send(self.class.acts_as_task_controller_config.task_class_name.pluralize).order('id DESC').page(page)

        # Check for updated tasks
        session[:task_updates] ||= {}
        task_updates = {}
        @new_tasks = []
        @updated_tasks = []
        @deleted_task_ids = []

        if @tasks
          @tasks.page(1).each do |task|
            task_updates[task.id] = task.updated_at
            @new_tasks << task unless session[:task_updates][task.id]
            @updated_tasks << task if session[:task_updates][task.id] && session[:task_updates][task.id] != task.updated_at
          end
          session[:task_updates].each{ |id, updated_at| @deleted_task_ids << id unless eval(self.class.acts_as_task_controller_config.task_class_name.camelize).find_by_id(id) }
          session[:task_updates] = task_updates
        end

        if request.xhr?
          # Load expanded_events from session if this is a AJAX-request
          @expanded_events = session[:acts_as_task_controller_expanded_events] || []
        else
          # Reset expanded_events if this is a regular request
          @expanded_events = session[:acts_as_task_controller_expanded_events] = []
        end

        respond_to do |format|
          format.html { render 'queue_dispatcher_views/my_events' }
          format.js do
            if params[:page]
              render
            else
              render 'queue_dispatcher_views/update_events'
            end
          end
        end
      end


      def expand_event
        @task = eval(self.class.acts_as_task_controller_config.task_class_name.camelize).find(params[:id])
        @expanded_events = session[:acts_as_task_controller_expanded_events] || []
        if @expanded_events.include? @task.id
          @expanded_events -= [@task.id]
        else
          @expanded_events |= [@task.id]
        end
        session[:acts_as_task_controller_expanded_events] = @expanded_events

        respond_to do |format|
          format.js { render 'queue_dispatcher_views/expand_event' }
        end
      end
    end

  end
end
