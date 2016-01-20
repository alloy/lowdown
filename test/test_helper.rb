$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'lowdown'

### Minitest

require 'minitest/spec'
require 'minitest/autorun'

module MiniTest::Assertions
  def assert_eventually_passes(timeout, block)
    require 'timeout'
    timeout ||= 2
    success = false
    begin
      Timeout.timeout(timeout) do
        sleep 0.1 until block.call
        success = true
      end
    rescue Timeout::Error
      success = false
    end
    assert success, "Block did return `true` before timeout (#{timeout} sec) was reached."
  end
end
Proc.infect_an_assertion :assert_eventually_passes, :must_eventually_pass



### Celluloid Logging

#$CELLULOID_DEBUG = true
#Celluloid.logger.level = Logger::DEBUG

def silence_logger
  logger, Celluloid.logger = Celluloid.logger, nil
  yield
ensure
  Celluloid.logger = logger
end



### Test Server

class MockAPNS
  class Request < Struct.new(:headers, :body)
    def initialize(*)
      super
      self.headers ||= {}
    end
  end

  attr_reader :requests

  def initialize
    @requests = []

    require "lowdown/mock"
    @context = Lowdown::Mock.certificate("com.example.MockAPNS").ssl_context
    # TODO figure out how to make the cert cerification work.
    #@context.verify_mode = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT

    @ssl = OpenSSL::SSL::SSLServer.new(TCPServer.new(0), @context)
  end

  def uri
    URI.parse("https://localhost:#{@ssl.addr[1]}")
  end

  def pkey
    @context.key
  end

  def certificate
    @context.cert
  end

  def run
    @thread = Thread.new do
      loop do
        sock = @ssl.accept

        conn = HTTP2::Server.new
        conn.on(:frame) do |bytes|
          sock.write bytes
        end

        conn.on(:stream) do |stream|
          buffer = ''
          request = Request.new

          stream.on(:headers) do |h|
            request.headers = Hash[*h.flatten]
            if request.headers["test-close-connection"]
              stream.close
              sock.close
            end
          end

          stream.on(:data) do |d|
            buffer << d
          end

          stream.on(:half_close) do
            request.body = buffer
            @requests << request

            # APNS only returns a body in case of an error
            #
            #response = "Hello HTTP 2.0! POST payload: #{buffer}"

            stream.headers({
              ":status" => "200",
              "apns-id" => request.headers["apns-id"],
              #"content-length" => response.bytesize.to_s,
              #"content-type" => "application/json",
            }, end_stream: true)

            #stream.data(response)
          end
        end

        while !sock.closed? && !(sock.eof? rescue true)
          data = sock.readpartial(1024)
          begin
            conn << data
          rescue => e
            puts "Exception: #{e}, #{e.message} - closing socket."
            sock.close
          end
        end
      end
    end

    @thread.abort_on_exception = true
  end
end

