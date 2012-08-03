module QueueDispatcher
  class RcAndMsg
    attr_accessor :rc, :output, :error_msg


    def self.good_rc(output = '', args = {})
      rc_and_msg = new
      rc_and_msg.good_rc(output, args)
    end


    def self.bad_rc(error_msg, args = {})
      rc_and_msg = new
      rc_and_msg.bad_rc(error_msg, args)
    end


    # Initializer
    def initialize(args = {})
      @rc = args[:rc].to_i if args[:rc]
      @output = args[:output]
      @error_msg = args[:error_msg]
      self
    end


    # Fake a good RC
    def good_rc(output, args = {})
      @rc = 0
      @output = output
      @error_msg = args[:error_msg]
      self
    end


    # Fake a bad RC
    def bad_rc(error_msg, args = {})
      @rc = 999
      @output = args[:output]
      @error_msg = error_msg
      self
    end


    # Addition
    def +(other)
      rc_and_msg = self.clone
      rc_and_msg.rc += other.rc
      rc_and_msg.output = rc_and_msg.output ? "#{output}\n#{other.output}" : other.output if other.output.present?
      rc_and_msg.error_msg = rc_and_msg.error_msg ? "#{error_msg}\n#{other.error_msg}" : other.error_msg if other.error_msg.present?
      rc_and_msg
    end


    # Return hash
    def to_hash
      { :rc => @rc, :output => @output, :error_msg => @error_msg }
    end
  end
end
