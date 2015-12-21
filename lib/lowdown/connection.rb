require "lowdown/threading"

require "http/2"
require "socket"
require "uri"
require "json"

module Lowdown
  class Connection
    Response = Struct.new(:notification, :headers, :body)

    def initialize(uri, certificate)
      @uri = URI(uri)
      @certificate = certificate
    end

    def open
      @main_queue = Threading::DispatchQueue.new
      @work_queue = Threading::DispatchQueue.new
      @requests   = Threading::Counter.new

      context = OpenSSL::SSL::SSLContext.new
      context.cert = @certificate
      @socket = TCPSocket.new(@uri.host, @uri.port)

      @ssl = OpenSSL::SSL::SSLSocket.new(@socket, context)
      @ssl.sync_close = true
      @ssl.hostname = @uri.hostname
      @ssl.connect

      @http = HTTP2::Client.new
      @http.on(:frame) do |bytes|
        @ssl.print(bytes)
        @ssl.flush
      end

      @thread = Thread.new do
        Thread.current.abort_on_exception = true
        until Thread.current[:should_exit] || @ssl.closed?
          @work_queue.drain!
          begin
            data = @ssl.read_nonblock(1024)
            begin
              @http << data
            rescue => e
              puts "Exception: #{e}, #{e.message} - closing socket."
              @ssl.close
            end
          rescue IO::WaitReadable
            # Reading would block.
          end
        end
      end
    end

    def close
      flush
      @thread[:should_exit] = true
      @thread.join
      @ssl.close
    end

    def flush
      until @work_queue.empty? && @requests.zero?
        @main_queue.drain!
        sleep 0.1
      end
    end

    def post(notification, &callback)
      @requests.increase!

      @work_queue.dispatch do
        uri = @uri + "/3/device/#{notification.token}"
        response = Response.new(notification)
        stream = @http.new_stream

        stream.on(:close) do
          @main_queue.dispatch do
            callback.call(response) if callback
            @requests.decrease!
          end
        end

        #stream.on(:half_close) do
          #puts 'closing client-end of the stream'
        #end

        stream.on(:headers) do |headers|
          response.headers = headers
        end

        stream.on(:data) do |data|
          response.body ||= ''
          response.body << data
        end

        body = notification.payload.to_json
        headers = {
          ":method"         => "POST",
          ":path"           => uri.path,
          "content-length"  => body.bytesize.to_s,
          "apns-id"         => notification.id.to_s,
          "apns-expiration" => notification.expiration.to_i.to_s,
          "apns-priority"   => notification.priority.to_s,
          "apns-topic"      => notification.topic,
        }

        stream.headers(headers, end_stream: false)
        stream.data(body, end_stream: true)
      end

      # The caller might be posting many notifications, so use this time to
      # also dispatch work onto the main thread.
      @main_queue.drain!
    end
  end
end
