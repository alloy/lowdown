require "lowdown/client/request_group"
require "lowdown/certificate"
require "lowdown/connection"
require "lowdown/notification"

require "uri"
require "json"

module Lowdown
  # The main class to use for interactions with the Apple Push Notification HTTP/2 service.
  #
  class Client
    # The details to connect to the development (sandbox) environment version of the APN service.
    #
    DEVELOPMENT_URI = URI.parse("https://api.development.push.apple.com:443")

    # The details to connect to the production environment version of the APN service.
    #
    PRODUCTION_URI = URI.parse("https://api.push.apple.com:443")

    # @!group Constructor Summary

    class << self
      # This is the most convenient constructor for regular use.
      #
      # It then calls {Client.client}.
      #
      # @param  [Boolean] production
      #         whether to use the production or the development environment.
      #
      # @param  [Certificate, String] certificate_or_data
      #         a configured Certificate or PEM data to construct a Certificate from.
      #
      # @raise  [ArgumentError]
      #         raised if the provided Certificate does not support the requested environment.
      #
      # @return (see Client#initialize)
      #
      def production(production, certificate_or_data)
        certificate = Certificate.certificate(certificate_or_data)
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

      # Creates a connection that connects to the specified `uri`.
      #
      # It then calls {Client.client_with_connection}.
      #
      # @note   The connection actor is terminated once the client is garbage collected.
      #
      # @param  [URI] uri
      #         the endpoint details of the service to connect to.
      #
      # @param  [Certificate, String] certificate_or_data
      #         a configured Certificate or PEM data to construct a Certificate from.
      #
      # @return (see Client#initialize)
      #
      def client(uri, certificate_or_data)
        certificate = Certificate.certificate(certificate_or_data)
        connection = Connection.new(uri, certificate.ssl_context)
        client_with_connection(connection, certificate).tap do |client|
          ObjectSpace.define_finalizer(client, generate_finalizer(connection))
        end
      end

      # Creates a Client configured with the `app_bundle_id` as its `default_topic`, in case the Certificate represents
      # a Universal Certificate.
      #
      # @param  [Connection] connection
      #         a Connection configured to connect to the remote service.
      #
      # @param  [Certificate] certificate
      #         a configured Certificate.
      #
      # @return (see Client#initialize)
      #
      def client_with_connection(connection, certificate)
        new(connection, certificate.universal? ? certificate.topics.first : nil)
      end

      private

      # Create the connection finalizer proc in isolation so that it does not capture the client and introduce a
      # retain-cycle.
      #
      # @param  [Celluloid::Proxy::Cell] connection
      #         the connection to terminate.
      #
      # @return [Proc]
      #         a finalizer proc that terminates the connection.
      #
      def generate_finalizer(connection)
        proc { connection.terminate }
      end
    end

    # You should normally use any of the other constructors to create a Client object.
    #
    # @param  [Connection] connection
    #         a Connection configured to connect to the remote service.
    #
    # @param  [String] default_topic
    #         the ‘topic’ to use if the Certificate is a Universal Certificate and a Notification doesn’t explicitely
    #         provide one.
    #
    # @return [Client]
    #         a new instance of Client.
    #
    def initialize(connection, default_topic = nil)
      @connection, @default_topic = connection, default_topic
    end

    # @!group Instance Attribute Summary

    # @return [Connection]
    #         a Connection configured to connect to the remote service.
    #
    attr_reader :connection

    # @return [String, nil]
    #         the ‘topic’ to use if the Certificate is a Universal Certificate and a Notification doesn’t explicitely
    #         provide one.
    #
    attr_reader :default_topic

    # @!group Instance Method Summary

    # Opens the connection to the service, yields a request group, and automatically closes the connection by the end of
    # the block.
    #
    # @see Connection#open
    # @see Client#group
    #
    # @yieldparam (see Client#group)
    #
    # @return [void]
    #
    def connect(&block)
      @connection.open
      if block
        begin
          group(&block)
        ensure
          disconnect
        end
      end
      nil
    end

    # Use this to group a batch of requests and halt the caller thread until all of the requests in the group have been
    # performed.
    #
    # It proxies {RequestGroup#send_notification} to {Client#send_notification}, but, unlike the latter, the request
    # callbacks are provided in the form of a block.
    #
    # @see    RequestGroup#send_notification
    #
    # @yieldparam [RequestGroup] group
    #         the request group object.
    #
    # @return [void]
    #
    def group
      group = RequestGroup.new(self)
      yield group
      group.flush
    ensure
      group.terminate
    end

    # Closes the connection to the service.
    #
    # @return [void]
    #
    def disconnect
      @connection.close
      nil
    end

    # Verifies the `notification` is valid and sends it to the remote service.
    #
    # @see Connection#post
    #
    # @note (see Connection#post)
    #
    # @param  [Notification] notification
    #         the notification object whose data to send to the service.
    #
    # @param  [Connection::DelegateProtocol] delegate
    #         an object that implements the connection delegate protocol.
    #
    # @param  [Object, nil] context
    #         any object that you want to be passed to the delegate once the response is back.
    #
    # @raise  [ArgumentError]
    #         raised if the Notification is not {Notification#valid?}.
    #
    # @return [void]
    #
    def send_notification(notification, delegate:, context: nil)
      raise ArgumentError, "Invalid notification: #{notification.inspect}" unless notification.valid?

      topic = notification.topic || @default_topic
      headers = {}
      headers["apns-expiration"] = (notification.expiration || 0).to_i
      headers["apns-id"]         = notification.formatted_id
      headers["apns-priority"]   = notification.priority     if notification.priority
      headers["apns-topic"]      = topic                     if topic

      body = notification.formatted_payload.to_json

      @connection.async.post(path: "/3/device/#{notification.token}",
                             headers: headers,
                             body: body,
                             delegate: delegate,
                             context: context)
    end
  end
end
