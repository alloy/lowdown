# frozen_string_literal: true

module Lowdown
  # A Notification holds the data and metadata about a Remote Notification.
  #
  # @see https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/APNsProviderAPI.html#//apple_ref/doc/uid/TP40008194-CH101-SW15
  # @see https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/TheNotificationPayload.html
  #
  class Notification
    # @!visibility private
    APS_KEYS = %w( alert badge sound content-available category ).freeze

    @id_mutex = Mutex.new
    @id_counter = 0

    def self.generate_id
      @id_mutex.synchronize do
        @id_counter += 1
      end
    end

    def self.format_id(id)
      padded = id.to_s.rjust(32, "0")
      [padded[0, 8], padded[8, 4], padded[12, 4], padded[16, 4], padded[20, 12]].join("-")
    end

    # @return [String]
    #         a device token.
    #
    attr_accessor :token

    # @return [Object, nil]
    #         a object that uniquely identifies this notification and is coercable to a String.
    #
    attr_accessor :id

    # @return [Time, nil]
    #         the time until which to retry delivery of a notification. By default it is only tried once.
    #
    attr_accessor :expiration

    # @return [Integer, nil]
    #         the priority at which to deliver this notification, which may be `10` or `5` if power consumption should
    #         be taken into consideration. Defaults to `10.
    #
    attr_accessor :priority

    # @return [String, nil]
    #         the ‘topic’ for this notification.
    #
    attr_accessor :topic

    # @return [Hash]
    #         the data payload for this notification.
    #
    attr_accessor :payload

    # @param [Hash] params
    #        a dictionary of keys described in the Instance Attribute Summary.
    #
    def initialize(params)
      params.each { |key, value| send("#{key}=", value) }
    end

    # @return [Boolean]
    #         whether this notification holds enough data and metadata to be sent to the APN service.
    #
    def valid?
      !!(@token && @payload)
    end

    def id
      @id ||= self.class.generate_id
    end

    # Formats the {#id} in the format required by the APN service, which is in groups of 8-4-4-12. It is padded with
    # leading zeroes.
    #
    # @return [String]
    #         the formatted ID.
    #
    def formatted_id
      @formatted_id ||= self.class.format_id(id)
    end

    # Unless the payload contains an `aps` entry, the payload is assumed to be a mix of APN defined attributes and
    # custom attributes and re-organized according to the specifications.
    #
    # @see https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/TheNotificationPayload.html#//apple_ref/doc/uid/TP40008194-CH107-SW1
    #
    # @return [Hash]
    #         the payload organized according to the APN specification.
    #
    def formatted_payload
      if @payload.key?("aps")
        @payload
      else
        payload = {}
        payload["aps"] = aps = {}
        @payload.each do |key, value|
          next if value.nil?
          key = key.to_s
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

