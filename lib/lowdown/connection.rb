require "lowdown/threading"
require "lowdown/response"

require "http/2"
require "openssl"
require "uri"
require "socket"

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
      @socket = TCPSocket.new(@uri.host, @uri.port)

      @ssl = OpenSSL::SSL::SSLSocket.new(@socket, @ssl_context)
      @ssl.sync_close = true
      @ssl.hostname = @uri.hostname
      @ssl.connect

      @http = HTTP2::Client.new
      @http.on(:frame) do |bytes|
        @ssl.print(bytes)
        @ssl.flush
      end

      @main_queue    = Threading::DispatchQueue.new
      @work_queue    = Threading::DispatchQueue.new
      @requests      = Threading::Counter.new
      @exceptions    = Queue.new
      @worker_thread = start_worker_thread!
    end

    # @return [Boolean]
    #         whether or not the Connection is open.
    #
    # @todo   Possibly add a HTTP/2 `PING` in the future.
    #
    def open?
      !@ssl.nil? && !@ssl.closed?
    end

    # Flushes the connection, terminates the worker thread, and closes the socket. Finally it peforms one more check for
    # pending jobs dispatched onto the main thread.
    #
    # @return [void]
    #
    def close
      flush

      @worker_thread[:should_exit] = true
      @worker_thread.join

      @ssl.close

      sleep 0.1
      @main_queue.drain!

      @socket = @ssl = @http = @main_queue = @work_queue = @requests = @exceptions = @worker_thread = nil
    end

    # Halts the calling thread until all dispatched requests have been performed.
    #
    # @return [void]
    #
    def flush
      until @work_queue.empty? && @requests.zero?
        @main_queue.drain!
        sleep 0.1
      end
    end

    # Sends the provided data as a `POST` request to the service.
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
      @work_queue.dispatch do
        headers = { ":method" => method.to_s, ":path" => path.to_s, "content-length" => body.bytesize.to_s }
        custom_headers.each { |k, v| headers[k] = v.to_s }

        stream = @http.new_stream
        response = Response.new

        stream.on(:headers) do |response_headers|
          response.headers = Hash[*response_headers.flatten]
        end

        stream.on(:data) do |response_data|
          response.raw_body ||= ''
          response.raw_body << response_data
        end

        stream.on(:close) do
          @main_queue.dispatch do
            callback.call(response)
            @requests.decrement!
          end
        end

        stream.headers(headers, end_stream: false)
        stream.data(body, end_stream: true)
      end

      # The caller might be posting many notifications, so use this time to also dispatch work onto the main thread.
      @main_queue.drain!
    end

    def start_worker_thread!
      Thread.new do
        until Thread.current[:should_exit] || @ssl.closed?
          # Run any dispatched jobs that add new requests.
          #
          # Re-raising a worker exception aids the development process. In production there’s no reason why this should
          # raise at all.
          if exception = @work_queue.drain!
            exception_occurred_in_worker(exception)
          end

          # Try to read data from the SSL socket without blocking. If it would block, catch the exception and restart
          # the loop.
          begin
            data = @ssl.read_nonblock(1024)
          rescue IO::WaitReadable
            data = nil
          rescue EOFError => exception
            exception_occurred_in_worker(exception)
            Thread.current[:should_exit] = true
            data = nil
          end

          # Process incoming HTTP data. If any processing exception occurs, fail the whole process.
          if data
            begin
              @http << data
            rescue Exception => exception
              @ssl.close
              exception_occurred_in_worker(exception)
            end
          end
        end
      end
    end

    # Raise the exception on the main thread and reset the number of in-flight requests so that a potential blocked
    # caller of `Connection#flush` will continue.
    #
    def exception_occurred_in_worker(exception)
      @exceptions << exception
      @main_queue.dispatch { raise @exceptions.pop }
      @requests.value = @http.active_stream_count
    end
  end
end
