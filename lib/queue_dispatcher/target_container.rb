module QueueDispatcher
  class TargetContainer
    attr_reader :payload

    def initialize(payload)
      @payload = payload
    end
  end
end
