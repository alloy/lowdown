require "lowdown/response"

require "http/2"

require "openssl"
require "socket"
require "timeout"
require "uri"

require "celluloid/current"
require "celluloid/io"

if HTTP2::VERSION == "0.8.0"
  # @!visibility private
  #
  # This monkey-patch ensures that we send the HTTP/2 connection preface before anything else.
  #
  # @see https://github.com/igrigorik/http-2/pull/44
  #
  class HTTP2::Client
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
  class HTTP2::Buffer
    def <<(x)
      super(x.force_encoding(Encoding::BINARY))
    end

    def prepend(x)
      super(x.force_encoding(Encoding::BINARY))
    end
  end
end

module Lowdown
  # The class responsible for managing the connection to the Apple Push Notification service.
  #
  # It manages both the SSL connection and processing of the HTTP/2 data sent back and forth over that connection.
  #
  class Connection
    include Celluloid::IO
    include Celluloid::Internals::Logger
    finalizer :close

    # @param  [URI, String] uri
    #         the details to connect to the APN service.
    #
    # @param  [OpenSSL::SSL::SSLContext] ssl_context
    #         a SSL context, configured with the certificate/key pair, which is used to connect to the APN service.
    #
    def initialize(uri, ssl_context)
      @uri, @ssl_context = URI(uri), ssl_context
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
    def open
      return if @connection
      debug "Opening new APNS connection."

      @connected = false
      @request_queue = []

      @connection = SSLSocket.new(TCPSocket.new(@uri.host, @uri.port), @ssl_context)
      @connection.sync_close = true
      @connection.connect

      @http = HTTP2::Client.new
      @http.on(:frame) do |bytes|
        @connection.print(bytes)
        @connection.flush
      end

      async.runloop
    end

    # Closes the connection and resets the internal state
    #
    # @return [void]
    #
    def close
      @connection.close if @connection
      @connection = @http = @connected = @request_queue = nil
    end

    # This performs a HTTP/2 PING to determine if the connection is actually alive. Be sure to not call this on a
    # sleeping connection, or it will be guaranteed to fail.
    #
    # @param  [Numeric] timeout
    #         the maximum amount of time to wait for the service to reply to the PING.
    #
    # @return [Boolean]
    #         whether or not the Connection is open.
    #
    def open?
      !@connection.nil? && !@connection.closed?
      #condition = Celluloid::Condition.new
      #future = Celluloid::Future.new { condition.wait }
      #unless @connection.nil? || @connection.closed?
        #@http.ping("whatever") { condition.signal(true) }
      #else
        #condition.signal(false)
      #end
      #future
    end

    private

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
      #         the context passed in when making the request.
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
      raise "First open the connection." unless @connection
      request('POST', path, headers, body, delegate, context)
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
        response.raw_body ||= ''
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
