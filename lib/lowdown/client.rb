require "lowdown/certificate"
require "lowdown/connection"
require "lowdown/notification"

require "uri"

module Lowdown
  class Client
    DEVELOPMENT_URI = URI.parse("https://api.development.push.apple.com:443")
    PRODUCTION_URI = URI.parse("https://api.push.apple.com:443")

    def self.production(production, certificate_or_data)
      client(production ? PRODUCTION_URI : DEVELOPMENT_URI, certificate_or_data)
    end

    def self.client(uri, certificate_or_data)
      if certificate_or_data.is_a?(Certificate)
        certificate = certificate_or_data
      else
        certificate = Certificate.from_pem_data(certificate_or_data)
      end
      default_topic = certificate.topics.first if certificate.universal?
      new(Connection.new(uri, certificate.ssl_context), default_topic)
    end

    attr_reader :connection, :default_topic

    def initialize(connection, default_topic = nil)
      @connection, @default_topic = connection, default_topic
    end

    def connect
      @connection.open
      if block_given?
        begin
          yield self
        ensure
          close
        end
      end
    end

    def flush
      @connection.flush
    end

    def close
      @connection.close
    end

    def send_notification(notification, &callback)
      topic = notification.topic || @default_topic
      headers = {}
      headers["apns-expiration"] = (notification.expiration || 0).to_i
      headers["apns-id"]         = notification.formatted_id if notification.id
      headers["apns-priority"]   = notification.priority     if notification.priority
      headers["apns-topic"]      = topic                     if topic

      body = { :aps => notification.payload }.to_json

      @connection.post("/3/device/#{notification.token}", headers, body, &callback)
    end
  end
end
