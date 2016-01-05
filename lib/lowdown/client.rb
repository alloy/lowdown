require "lowdown/certificate"
require "lowdown/connection"
require "lowdown/notification"

require "uri"
require "json"

module Lowdown
  class Client
    DEVELOPMENT_URI = URI.parse("https://api.development.push.apple.com:443")
    PRODUCTION_URI = URI.parse("https://api.push.apple.com:443")

    def self.production(production, certificate_or_data)
      certificate = Lowdown.Certificate(certificate_or_data)
      if production
        unless certificate.production?
          raise ArgumentError, "The specified certificate is not usable with the production environment."
        end
      else
        unless certificate.development?
          raise ArgumentError, "The specified certificate is not usable with the development environment."
        end
      end
      client(production ? PRODUCTION_URI : DEVELOPMENT_URI, certificate)
    end

    def self.client(uri, certificate_or_data)
      certificate = Lowdown.Certificate(certificate_or_data)
      client_with_connection(Connection.new(uri, certificate.ssl_context), certificate)
    end

    def self.client_with_connection(connection, certificate)
      new(connection, certificate.universal? ? certificate.topics.first : nil)
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
      raise ArgumentError, "Invalid notification: #{notification.inspect}" unless notification.valid?

      topic = notification.topic || @default_topic
      headers = {}
      headers["apns-expiration"] = (notification.expiration || 0).to_i
      headers["apns-id"]         = notification.formatted_id if notification.id
      headers["apns-priority"]   = notification.priority     if notification.priority
      headers["apns-topic"]      = topic                     if topic

      body = notification.formatted_payload.to_json

      @connection.post("/3/device/#{notification.token}", headers, body, &callback)
    end
  end
end
