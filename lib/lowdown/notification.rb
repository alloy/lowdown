module Lowdown
  # For payload documentation see: https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/TheNotificationPayload.html#//apple_ref/doc/uid/TP40008194-CH107-SW1
  #
  class Notification
    APS_KEYS = [:alert, :badge, :sound, :content_available, :category].freeze

    attr_accessor :token, :id, :expiration, :priority, :topic, :payload

    def initialize(params)
      params.each { |key, value| send("#{key}=", value) }
    end

    def valid?
      !!(@token && @payload)
    end

    def formatted_id
      if @id
        padded = @id.to_s.rjust(32, "0")
        [padded[0,8], padded[8,4], padded[12,4], padded[16,4], padded[20,12]].join("-")
      end
    end

    def formatted_payload
      if @payload.has_key?(:aps)
        @payload
      else
        payload = {}
        payload[:aps] = aps = {}
        @payload.each do |key, value|
          key = key.to_sym
          if APS_KEYS.include?(key)
            aps[key] = value
          else
            payload[key] = value
          end
        end
        payload
      end
    end
  end
end
