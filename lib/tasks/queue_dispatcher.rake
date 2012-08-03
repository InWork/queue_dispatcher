namespace :queue_dispatcher do
  desc "Sync extra files from QueueDispatcher gem."
  task :sync do
    system "rsync -ruv #{File.dirname(__FILE__)}/../../script #{Rails.root}"
  end
end
