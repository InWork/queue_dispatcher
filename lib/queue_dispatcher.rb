require 'rails'
require 'queue_dispatcher'
require 'queue_dispatcher/acts_as_task'
require 'queue_dispatcher/acts_as_task_queue'
require 'queue_dispatcher/acts_as_task_controller'
require 'queue_dispatcher/deserialization_error'
require 'queue_dispatcher/message_sending'
require 'queue_dispatcher/target_container'
require 'queue_dispatcher/qd_logger'
require 'queue_dispatcher/rc_and_msg'
require 'queue_dispatcher/yaml_ext'

module QueueDispatcher
  class Engine < ::Rails::Engine
  end
end

ActiveRecord::Base.send(:include, QueueDispatcher::ActsAsTask)
ActiveRecord::Base.send(:include, QueueDispatcher::ActsAsTaskQueue)
ActionController::Base.send(:include, QueueDispatcher::ActsAsTaskController)
Object.send(:include, QueueDispatcher::MessageSending)
