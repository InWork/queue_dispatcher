module TasksHelper
  def icon_for_task task
    icon = 'icon_warning.gif'
    alt  = 'Unknwon'

    if task.pending? && ! task.reloading_config?
      icon = 'icon_pending.gif'
      alt  = 'Pending'
    elsif task.init_queue? || task.reloading_config?
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
    end

    image_tag(icon, :alt => alt)
  end
end
