module TasksHelper
  def icon_for_task task
    icon = 'icon_warning.gif'
    alt  = 'Unknwon'

    if task.pending?
      if task.reloading_config?
        icon = 'icon_init_queue.gif'
        alt  = 'Reloading Config'
      else
        icon = 'icon_pending.gif'
        alt  = 'Pending'
      end
    elsif task.init_queue?
      icon = 'icon_init_queue.gif'
      alt  = 'Initialize Queue'
    elsif task.acquire_lock?
      icon = 'icon_acquire_lock.png'
      alt  = 'Acquire Lock'
    elsif task.running?
      icon = 'icon_running.gif'
      alt  = 'Running'
    elsif task.successful?
      icon = 'icon_successful.png'
      alt  = 'Successful'
    elsif task.error?
      icon = 'icon_error.png'
      alt  = 'Error!'
    elsif task.aborted?
      icon = 'icon_aborted.png'
      alt  = 'Aborted!'
    end

    image_tag(icon, :alt => alt)
  end
end
