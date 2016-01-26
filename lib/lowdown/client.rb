require "lowdown/client/request_group"
require "lowdown/certificate"
require "lowdown/connection"
require "lowdown/connection/monitor"
require "lowdown/notification"

require "uri"
require "json"

module Lowdown
  # The main class to use for interactions with the Apple Push Notification HTTP/2 service.
  #
  # Important connection configuration options are `pool_size` and `keep_alive`. The former specifies the number of
  # simultaneous connections the client should make and the latter is key for long running processes.
  #
  class Client
    # The details to connect to the development (sandbox) environment version of the APN service.
    #
    DEVELOPMENT_URI = URI.parse("https://api.development.push.apple.com:443")

    # The details to connect to the production environment version of the APN service.
    #
    PRODUCTION_URI = URI.parse("https://api.push.apple.com:443")

    # @!group Constructor Summary

    # This is the most convenient constructor for regular use.
    #
    # @param  [Boolean] production
    #         whether to use the production or the development environment.
    #
    # @param  [Certificate, String] certificate
    #         a configured Certificate or PEM data to construct a Certificate from.
    #
    # @param  [Fixnum] pool_size
    #         the number of connections to make.
    #
    # @param  [Boolean] keep_alive
    #         when `true` this will make connections, new and restarted, immediately connect to the remote service. Use
    #         this if you want to keep connections open indefinitely.
    #
    # @raise  [ArgumentError]
    #         raised if the provided Certificate does not support the requested environment.
    #
    # @return (see Client#initialize)
    #
    def self.production(production, certificate:, pool_size: 1, keep_alive: false)
      certificate = Certificate.certificate(certificate)
      if production
        unless certificate.production?
          raise ArgumentError, "The specified certificate is not usable with the production environment."
        end
      else
        unless certificate.development?
          raise ArgumentError, "The specified certificate is not usable with the development environment."
        end
      end
      client(uri: production ? PRODUCTION_URI : DEVELOPMENT_URI,
             certificate: certificate,
             pool_size: pool_size,
             keep_alive: keep_alive)
    end

    # Creates a connection pool that connects to the specified `uri`.
    #
    # @param  [URI] uri
    #         the endpoint details of the service to connect to.
    #
    # @param  [Certificate, String] certificate
    #         a configured Certificate or PEM data to construct a Certificate from.
    #
    # @param  [Fixnum] pool_size
    #         the number of connections to make.
    #
    # @param  [Boolean] keep_alive
    #         when `true` this will make connections, new and restarted, immediately connect to the remote service. Use
    #         this if you want to keep connections open indefinitely.
    #
    # @return (see Client#initialize)
    #
    def self.client(uri:, certificate:, pool_size: 1, keep_alive: false)
      certificate = Certificate.certificate(certificate)
      connection_pool = Connection.pool(size: pool_size, args: [uri, certificate.ssl_context, keep_alive])
      client_with_connection(connection_pool, certificate: certificate)
    end

    # Creates a Client configured with the `app_bundle_id` as its `default_topic`, in case the Certificate represents
    # a Universal Certificate.
    #
    # @param  [Connection, Celluloid::Supervision::Container::Pool<Connection>] connection
    #         a single Connection or a pool of Connection actors configured to connect to the remote service.
    #
    # @param  [Certificate] certificate
    #         a configured Certificate.
    #
    # @return (see Client#initialize)
    #
    def self.client_with_connection(connection, certificate:)
      new(connection: connection, default_topic: certificate.universal? ? certificate.topics.first : nil)
    end

    # You should normally use any of the other constructors to create a Client object.
    #
    # @param  [Connection, Celluloid::Supervision::Container::Pool<Connection>] connection
    #         a single Connection or a pool of Connection actors configured to connect to the remote service.
    #
    # @param  [String] default_topic
    #         the ‘topic’ to use if the Certificate is a Universal Certificate and a Notification doesn’t explicitely
    #         provide one.
    #
    # @return [Client]
    #         a new instance of Client.
    #
    def initialize(connection:, default_topic: nil)
      @connection, @default_topic = connection, default_topic
    end

    # @!group Instance Attribute Summary

    # @return [Connection, Celluloid::Supervision::Container::Pool<Connection>]
    #         a single Connection or a pool of Connection actors configured to connect to the remote service.
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
    # @note   Don’t use this if you opted to keep a pool of connections alive.
    #
    # @see    Connection#connect
    # @see    Client#group
    #
    # @yieldparam (see Client#group)
    #
    # @return [void]
    #
    def connect(&block)
      if @connection.respond_to?(:actors)
        @connection.actors.each { |connection| connection.async.connect }
      else
        @connection.async.connect
      end
      if block
        begin
          group(&block)
        ensure
          disconnect
        end
      end
    end

    # Closes the connection to the service.
    #
    # @see    Connection#disconnect
    #
    # @return [void]
    #
    def disconnect
      @connection.disconnect
    rescue Celluloid::DeadActorError
      # Rescue this exception instead of calling #alive? as that only works on an actor, not a pool.
    end

    # Use this to group a batch of requests and halt the caller thread until all of the requests in the group have been
    # performed.
    #
    # It proxies {RequestGroup#send_notification} to {Client#send_notification}, but, unlike the latter, the request
    # callbacks are provided in the form of a block.
    #
    # @note   Do **not** share the yielded group across threads. For the duration of the block, In the connection will
    #         be monitored for exceptions and, if any, raise them on the calling thread.
    #
    # @see    RequestGroup#send_notification
    # @see    Connection::Monitor
    #
    # @yieldparam [RequestGroup] group
    #         the request group object.
    #
    # @return [void]
    #
    def group
      group = RequestGroup.new(self)
      monitor do
        yield group
        group.flush
      end
    ensure
      group.terminate
    end

    # Creates a {Connection::Monitor} and monitors the connection for the duration of the given block. Exceptions that
    # occur on the connection, or connections in the pool, will be raised on the caller thread. Thus you should halt the
    # caller thread while waiting for your work to finish.
    #
    # This is automatically used by {#group}.
    #
    # @return [void]
    #
    def monitor
      monitor = Connection::Monitor.monitor(@connection) if @connection.is_a?(Celluloid) # Ignore mock connections.
      yield
    ensure
      monitor.terminate if monitor
    end

    # Verifies the `notification` is valid and then sends it to the remote service. Response feedback is provided via
    # a delegate mechanism.
    #
    # @note   In general, you will probably want to use {#group} to be able to use {RequestGroup#send_notification},
    #         which takes a traditional blocks-based callback approach.
    #
    # @see    Connection#post
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
