require "lowdown/threading"
require "lowdown/response"

require "http/2"

require "openssl"
require "socket"
require "timeout"
require "uri"

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

    # Creates a new SSL connection to the service, a HTTP/2 client, and starts off a worker thread.
    #
    # @return [void]
    #
    def open
      raise "Connection already open." if @worker
      @requests = Threading::Counter.new
      @worker = Worker.new(@uri, @ssl_context)
    end

    # Flushes the connection, terminates the worker thread, and closes the socket. Finally it peforms one more check for
    # pending jobs dispatched onto the main thread.
    #
    # @return [void]
    #
    def close
      return unless @worker
      flush
      @worker.stop
      @worker = @requests = nil
    end

    # This performs a HTTP/2 PING to determine if the connection is actually alive.
    #
    # @param  [Numeric] timeout
    #         the maximum amount of time to wait for the service to reply to the PING.
    #
    # @return [Boolean]
    #         whether or not the Connection is open.
    #
    def open?(timeout = 5)
      return false unless @worker
      Timeout.timeout(timeout) do
        caller_thread = Thread.current
        @worker.enqueue do |http|
          http.ping('12345678') { caller_thread.run }
        end
        Thread.stop
      end
      # If the thread was woken-up before the timeout was reached, that means we got a PONG.
      true
    rescue Timeout::Error
      false
    end

    # Halts the calling thread until all dispatched requests have been performed.
    #
    # @return [void]
    #
    def flush
      return unless @worker
      sleep 0.1 until !@worker.alive? || @worker.empty? && @requests.zero?
    end

    # Sends the provided data as a `POST` request to the service.
    #
    # @note The callback is performed on a different thread, dedicated to perfoming these callbacks.
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
    # @yield  [response]
    #         Called when the request is finished and a response is available.
    #
    # @yieldparam [Response] response
    #         The Response that holds the status data that came back from the service.
    #
    # @return [void]
    #
    def post(path, headers, body, &callback)
      request('POST', path, headers, body, &callback)
    end

    private

    def request(method, path, custom_headers, body, &callback)
      @requests.increment!
      @worker.enqueue do |http, callbacks|
        headers = { ":method" => method.to_s, ":path" => path.to_s, "content-length" => body.bytesize.to_s }
        custom_headers.each { |k, v| headers[k] = v.to_s }

        stream = http.new_stream
        response = Response.new

        stream.on(:headers) do |response_headers|
          response.headers = Hash[*response_headers.flatten]
        end

        stream.on(:data) do |response_data|
          response.raw_body ||= ''
          response.raw_body << response_data
        end

        stream.on(:close) do
          callbacks.enqueue do
            callback.call(response)
            @requests.decrement!
          end
        end

        stream.headers(headers, end_stream: false)
        stream.data(body, end_stream: true)
      end
    end

    # @!visibility private
    #
    # Creates a new worker thread which maintains all its own state:
    # * SSL connection
    # * HTTP2 client
    # * Another thread from where request callbacks are ran
    #
    class Worker < Threading::Consumer
      def initialize(uri, ssl_context)
        @uri, @ssl_context = uri, ssl_context

        # Start the worker thread.
        #
        # Because a max size of 0 is not allowed, create with an initial max size of 1 and add a dummy job. This is so
        # that any attempt to add a new job to the queue is going to halt the calling thread *until* we change the max.
        super(queue: Thread::SizedQueue.new(1))
        # Put caller thread into sleep until connected.
        Thread.stop
      end

      # Tells the runloop to stop and halts the caller until finished.
      #
      # @return [void]
      #
      def stop
        thread[:should_exit] = true
        thread.join
      end

      private

      attr_reader :callbacks

      def post_runloop
        @callbacks.kill
        @ssl.close
        super
      end

      def pre_runloop
        super

        # Setup the request callbacks consumer here so its parent thread will be this worker thread.
        @callbacks = Threading::Consumer.new

        @ssl = OpenSSL::SSL::SSLSocket.new(TCPSocket.new(@uri.host, @uri.port), @ssl_context)
        @ssl.sync_close = true
        @ssl.hostname = @uri.hostname
        @ssl.connect

        @http = HTTP2::Client.new
        @http.on(:frame) do |bytes|
          # This is going to be performed on the worker thread and thus does *not* write to @ssl from another thread than
          # the thread it’s being read from.
          @ssl.print(bytes)
          @ssl.flush
        end
      end

      def change_to_connected_state
        queue.max = @http.remote_settings[:settings_max_concurrent_streams]
        @connected = true
        parent_thread.run
      end

      # @note Only made into a method so it can be overriden from the tests, because our test setup doesn’t behave the
      #       same as the real APNS service.
      #
      def http_connected?
        @http.state == :connected
      end

      # Start the main IO and HTTP processing loop.
      def runloop
        until thread[:should_exit] || @ssl.closed?
          # Once connected, add requests while the max stream count has not yet been reached.
          if !@connected
            change_to_connected_state if http_connected?
          elsif @http.active_stream_count < queue.max
            # Run dispatched jobs that add new requests.
            perform_job(true, @http, @callbacks)
          end
          # Try to read data from the SSL socket without blocking and process it.
          begin
            @http << @ssl.read_nonblock(1024)
          rescue IO::WaitReadable
          end
        end
      end
    end
  end
end
