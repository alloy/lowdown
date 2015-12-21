module Lowdown
  class Notification
    attr_accessor :token, :id, :expiration, :priority, :topic, :payload

    def initialize(params)
      params.each { |key, value| send("#{key}=", value) }
    end
  end
end
