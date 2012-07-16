module QdLogger
  attr_accessor :logger

  def initialize_logger(logger = nil)
    @logger = logger || Logger.new("#{File.expand_path(Rails.root)}/log/queue_dispatcher.log")
  end

  # Write a standart log message
  def log(args = {})
    sev = args[:sev] || :info
    msg = Time.now.to_s + " #{sev.to_s.upcase} #{$$} (#{self.class.name}): " + args[:msg]
    logger.send(sev, msg) if logger
    puts "#{sev.to_s.upcase}: #{args[:msg]}" if logger.nil? || args[:print_log]
  end
end
