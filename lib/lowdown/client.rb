# frozen_string_literal: true

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

    # The default timeout for {#group}.
    #
    DEFAULT_GROUP_TIMEOUT = 3600

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
    # @param  [Class] connection_class
    #         the connection class to instantiate, this can for instan be {Mock::Connection} during testing.
    #
    # @raise  [ArgumentError]
    #         raised if the provided Certificate does not support the requested environment.
    #
    # @return (see Client#initialize)
    #
    def self.production(production, certificate:, pool_size: 1, keep_alive: false, connection_class: Connection)
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
             keep_alive: keep_alive,
             connection_class: connection_class)
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
    # @param  [Class] connection_class
    #         the connection class to instantiate, this can for instan be {Mock::Connection} during testing.
    #
    # @return (see Client#initialize)
    #
    def self.client(uri:, certificate:, pool_size: 1, keep_alive: false, connection_class: Connection)
      certificate = Certificate.certificate(certificate)
      connection_class ||= Connection
      connection_pool = connection_class.pool(size: pool_size, args: [uri, certificate.ssl_context, keep_alive])
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
    # @param  [Numeric] group_timeout
    #         the maximum amount of time to wait for a request group to halt the caller thread. Defaults to 1 hour.
    #
    # @yieldparam (see Client#group)
    #
    # @return [void]
    #
    def connect(group_timeout: nil, &block)
      if @connection.respond_to?(:actors)
        @connection.actors.each { |connection| connection.async.connect }
      else
        @connection.async.connect
      end
      if block
        begin
          group(timeout: group_timeout, &block)
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
      if @connection.respond_to?(:actors)
        @connection.actors.each do |connection|
          connection.async.disconnect if connection.alive?
        end
      else
        @connection.async.disconnect if @connection.alive?
      end
    end

    # Use this to group a batch of requests and halt the caller thread until all of the requests in the group have been
    # performed.
    #
    # It proxies {RequestGroup#send_notification} to {Client#send_notification}, but, unlike the latter, the request
    # callbacks are provided in the form of a block.
    #
    # @note   Do **not** share the yielded group across threads.
    #
    # @see    RequestGroup#send_notification
    # @see    Connection::Monitor
    #
    # @param  [Numeric] timeout
    #         the maximum amount of time to wait for a request group to halt the caller thread. Defaults to 1 hour.
    #
    # @yieldparam [RequestGroup] group
    #         the request group object.
    #
    # @raise  [Exception]
    #         if a connection in the pool has died during the execution of this group, the reason for its death will be
    #         raised.
    #
    # @return [void]
    #
    def group(timeout: nil)
      group = nil
      monitor do |condition|
        group = RequestGroup.new(self, condition)
        yield group
        if !group.empty? && exception = condition.wait(timeout || DEFAULT_GROUP_TIMEOUT)
          raise exception
        end
      end
    ensure
      group.try :terminate
    end

    # Registers a condition object with the connection pool, for the duration of the given block. It either returns an
    # exception that caused a connection to die, or whatever value you signal to it.
    #
    # This is automatically used by {#group}.
    #
    # @yieldparam [Connection::Monitor::Condition] condition
    #         the monitor condition object.
    #
    # @return [void]
    #
    def monitor
      condition = Connection::Monitor::Condition.new
      if defined?(Mock::Connection) && @connection.class == Mock::Connection
        yield condition
      else
        begin
          @connection.__register_lowdown_crash_condition__(condition)
          yield condition
        ensure
          @connection.__deregister_lowdown_crash_condition__(condition)
        end
      end
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

