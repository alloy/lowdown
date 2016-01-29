# This file can’t specify that it uses frozen string literals yet, because the strings’ encodings are modified when
# passed to the http-2 gem.

require "lowdown/response"

require "uri"

require "celluloid/current"
require "celluloid/io"
require "http/2"

if HTTP2::VERSION == "0.8.0"
  # @!visibility private
  #
  module HTTP2
    # @!visibility private
    #
    # This monkey-patch ensures that we send the HTTP/2 connection preface before anything else.
    #
    # @see https://github.com/igrigorik/http-2/pull/44
    #
    class Client
      def connection_management(frame)
        if @state == :waiting_connection_preface
          send_connection_preface
          connection_settings(frame)
        else
          super(frame)
        end
      end
    end

    # @!visibility private
    #
    # These monkey-patches ensure that data added to a buffer has a binary encoding, as to not lead to encoding clashes.
    #
    # @see https://github.com/igrigorik/http-2/pull/46
    #
    class Buffer
      def <<(x)
        super(x.force_encoding(Encoding::BINARY))
      end

      def prepend(x)
        super(x.force_encoding(Encoding::BINARY))
      end
    end
  end
end

module Lowdown
  # The class responsible for managing the connection to the Apple Push Notification service.
  #
  # It manages both the SSL connection and processing of the HTTP/2 data sent back and forth over that connection.
  #
  class Connection
    class TimedOut < StandardError; end

    CONNECT_RETRIES       = 5
    CONNECT_RETRY_BACKOFF = 5
    CONNECT_TIMEOUT       = 10
    HEARTBEAT_INTERVAL    = 10
    HEARTBEAT_TIMEOUT     = CONNECT_TIMEOUT

    include Celluloid::IO
    include Celluloid::Internals::Logger
    finalizer :disconnect

    # @param  [URI, String] uri
    #         the details to connect to the APN service.
    #
    # @param  [OpenSSL::SSL::SSLContext] ssl_context
    #         a SSL context, configured with the certificate/key pair, which is used to connect to the APN service.
    #
    # @param  [Boolean] connect
    #         whether or not to immediately connect on initialization.
    #
    def initialize(uri, ssl_context, connect = true)
      @uri, @ssl_context = URI(uri), ssl_context
      reset_state!

      if connect
        # This ensures that calls to the public #connect method are ignored while already connecting.
        @connecting = true
        async.connect!
      end
    end

    # @return [URI]
    #         the details to connect to the APN service.
    #
    attr_reader :uri

    # @return [OpenSSL::SSL::SSLContext]
    #         a SSL context, configured with the certificate/key pair, which is used to connect to the APN service.
    #
    attr_reader :ssl_context

    # Creates a new SSL connection to the service, a HTTP/2 client, and starts off the main runloop.
    #
    # @return [void]
    #
    def connect
      connect! unless @connecting
    end

    # Closes the connection and resets the internal state
    #
    # @return [void]
    #
    def disconnect
      @connection.close if @connection
      @heartbeat.cancel if @heartbeat
      reset_state!
    end

    # @return [Boolean]
    #         whether or not the Connection is open.
    #
    def connected?
      !@connection.nil? && !@connection.closed?
    end

    # This performs a HTTP/2 PING to determine if the connection is actually alive. Be sure to not call this on a
    # sleeping connection, or it will be guaranteed to fail.
    #
    # @note   This halts the caller thread until a reply is received. You should call this on a future and possibly set
    #         a timeout.
    #
    # @return [Boolean]
    #         whether or not a reply was received.
    #
    def ping
      if connected?
        condition = Celluloid::Condition.new
        @http.ping("whatever") { condition.signal(true) }
        condition.wait
      else
        false
      end
    end

    private

    def connect!(tries = 0)
      return if @connection
      @connecting = true

      info "Opening APNS connection."

      # Celluloid::IO::DNSResolver bug. In case there is no connection at all:
      # 1. This results in `nil`:
      #    https://github.com/celluloid/celluloid-io/blob/85cee9da22ef5e94ba0abfd46454a2d56572aff4/lib/celluloid/io/dns_resolver.rb#L32
      # 2. This tries to `NilClass#send` the hostname:
      #    https://github.com/celluloid/celluloid-io/blob/85cee9da22ef5e94ba0abfd46454a2d56572aff4/lib/celluloid/io/dns_resolver.rb#L44
      begin
        socket = TCPSocket.new(@uri.host, @uri.port)
      rescue NoMethodError
        raise SocketError, "(Probably) getaddrinfo: nodename nor servname provided, or not known"
      end

      @connection = SSLSocket.new(socket, @ssl_context)
      begin
        timeout(CONNECT_TIMEOUT) { @connection.connect }
      rescue Celluloid::TimedOut
        raise TimedOut, "Initiating SSL socket timed-out."
      end

      @http = HTTP2::Client.new
      @http.on(:frame) do |bytes|
        @connection.print(bytes)
        @connection.flush
      end

      async.runloop

    rescue Celluloid::TaskTerminated, Celluloid::DeadActorError
      # These are legit, let them bubble up.
      raise
    rescue Exception => e
      # The main reason to do connect retries ourselves, instead of letting it up a supervisor/pool, is because a pool
      # goes into a bad state if a connection crashes on initialization.
      @connection.close if @connection && !@connection.closed?
      @connection = @http = nil
      if tries < CONNECT_RETRIES
        tries += 1
        delay = tries * CONNECT_RETRY_BACKOFF
        error("#{e.class}: #{e.message} - retrying in #{delay} seconds (#{tries}/#{CONNECT_RETRIES})")
        after(delay) { async.connect!(tries) }
        return
      else
        raise
      end
    end

    def reset_state!
      @connecting = false
      @connected = false
      @request_queue = []
      @connection = @http = @heartbeat = nil
    end

    # The main IO runloop that feeds data from the remote service into the HTTP/2 client.
    #
    # It should only ever exit gracefully if the connection has been closed with {#close} or the actor has been
    # terminated. Otherwise this method may raise any connection or HTTP/2 parsing related exception, which will kill
    # the actor and, if supervised, start a new connection.
    #
    # @return [void]
    #
    def runloop
      loop do
        begin
          @http << @connection.readpartial(1024)
          change_to_connected_state if !@connected && @http.state == :connected
        rescue IOError => e
          if @connection
            raise
          else
            # Connection was closed by us and set to nil, so exit gracefully
            break
          end
        end
      end
    end

    # Called when the HTTP client changes its state to `:connected`.
    #
    # @return [void]
    #
    def change_to_connected_state
      @max_stream_count = @http.remote_settings[:settings_max_concurrent_streams]
      @connected = true

      debug "APNS connection established. Maximum number of concurrent streams: #{@max_stream_count}. " \
            "Flushing #{@request_queue.size} enqueued requests."

      @request_queue.size.times do
        async.try_to_perform_request!
      end

      @heartbeat = every(HEARTBEAT_INTERVAL) do
        debug "Sending heartbeat ping"
        begin
          future.ping.call(HEARTBEAT_TIMEOUT)
        rescue Celluloid::TimedOut
          raise TimedOut, "Heartbeat ping timed-out."
        end
      end
    end

    public

    # This module describes the interface that your delegate object should conform to, but it is not required to include
    # this module in your class, it mainly serves a documentation purpose.
    #
    module DelegateProtocol
      # Called when a request is finished and a response is available.
      #
      # @note   (see Connection#post)
      #
      # @param  [Response] response
      #         the Response that holds the status data that came back from the service.
      #
      # @param  [Object, nil] context
      #         the context passed in when making the request, which can be any type of object or an array of objects.
      #
      # @return [void]
      #
      def handle_apns_response(response, context:)
        raise NotImplementedError
      end
    end

    # Sends the provided data as a `POST` request to the service.
    #
    # @note   It is strongly advised that the delegate object is a Celluloid actor and that you pass in an async proxy
    #         of that object, but that is not required. If you do not pass in an actor, then be advised that the
    #         callback will run on this connection’s private thread and thus you should not perform long blocking
    #         operations.
    #
    # @param  [String] path
    #         the request path, which should be `/3/device/<device-token>`.
    #
    # @param  [Hash] headers
    #         the additional headers for the request. By default it sends `:method`, `:path`, and `content-length`.
    #
    # @param  [String] body
    #         the (JSON) encoded payload data to send to the service.
    #
    # @param  [DelegateProtocol] delegate
    #         an object that implements the delegate protocol.
    #
    # @param  [Object, nil] context
    #         any object that you want to be passed to the delegate once the response is back.
    #
    # @return [void]
    #
    def post(path:, headers:, body:, delegate:, context: nil)
      request("POST", path, headers, body, delegate, context)
    end

    private

    Request = Struct.new(:headers, :body, :delegate, :context)

    def request(method, path, custom_headers, body, delegate, context)
      headers = { ":method" => method.to_s, ":path" => path.to_s, "content-length" => body.bytesize.to_s }
      custom_headers.each { |k, v| headers[k] = v.to_s }

      request = Request.new(headers, body, delegate, context)
      @request_queue << request

      try_to_perform_request!
    end

    def try_to_perform_request!
      unless @connected
        debug "Defer performing request, because the connection has not been established yet"
        return
      end

      unless @http.active_stream_count < @max_stream_count
        debug "Defer performing request, because the maximum concurren stream count has been reached"
        return
      end

      unless request = @request_queue.shift
        debug "Defer performing request, because the request queue is empty"
        return
      end

      apns_id = request.headers["apns-id"]
      debug "[#{apns_id}] Performing request"

      stream = @http.new_stream
      response = Response.new

      stream.on(:headers) do |headers|
        headers = Hash[*headers.flatten]
        debug "[#{apns_id}] Got response headers: #{headers.inspect}"
        response.headers = headers
      end

      stream.on(:data) do |data|
        debug "[#{apns_id}] Got response data: #{data}"
        response.raw_body ||= ""
        response.raw_body << data
      end

      stream.on(:close) do
        debug "[#{apns_id}] Request completed"
        request.delegate.handle_apns_response(response, context: request.context)
        async.try_to_perform_request!
      end

      stream.headers(request.headers, end_stream: false)
      stream.data(request.body, end_stream: true)
    end
  end
end

