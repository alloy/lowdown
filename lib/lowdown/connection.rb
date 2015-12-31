require "lowdown/threading"
require "lowdown/response"

require "http/2"
require "openssl"
require "uri"
require "socket"

module Lowdown
  class Connection
    attr_reader :uri, :ssl_context

    def initialize(uri, ssl_context)
      @uri, @ssl_context = URI(uri), ssl_context
    end

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

    def open?
      !@ssl.nil? && !@ssl.closed?
    end

    # Terminates the worker thread and closes the socket. Finally it peforms one more check for pending jobs dispatched
    # onto the main thread.
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

    def flush
      until @work_queue.empty? && @requests.zero?
        @main_queue.drain!
        sleep 0.1
      end
    end

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
