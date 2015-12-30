require "lowdown/connection"
require "lowdown/notification"

require "uri"

module Lowdown
  class Client
    DEVELOPMENT_URI = URI.parse("https://api.development.push.apple.com:443")
    PRODUCTION_URI = URI.parse("https://api.push.apple.com:443")

    attr_reader :connection, :default_topic

    def initialize(uri, certificate_data)
      certificate = OpenSSL::X509::Certificate.new(certificate_data)
      pkey = OpenSSL::PKey::RSA.new(certificate_data, nil)

      # TODO The docs say that topic can be optional, but it seems required in our case.
      #      Figure out if it’s because we have a watch app and if that's encoded into the
      #      certificate and base us including the default topic on that.
      #
      #      See section about the `1.2.840.113635.100.6.3.6` certificate extension:
      #      https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/APNsProviderAPI.html#//apple_ref/doc/uid/TP40008194-CH101-SW1
      #
      _, bundle_id, __ = certificate.subject.to_a.find { |key, *_| key == 'UID' }
      @default_topic = bundle_id

      @connection = Connection.new(uri, certificate, pkey)
    end

    def connect
      @connection.open
    end

    def flush
      @connection.flush
    end

    def close
      @connection.close
    end

    def send_notification(notification, &callback)
      body = { :aps => notification.payload }.to_json

      headers = {
        "apns-expiration" => (notification.expiration || 0).to_i,
        "apns-topic"      => notification.topic || @default_topic,
      }
      headers["apns-id"]       = notification.formatted_id if notification.id
      headers["apns-priority"] = notification.priority     if notification.priority

      @connection.post("/3/device/#{notification.token}", headers, body, &callback)
    end
  end
end
