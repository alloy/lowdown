$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'lowdown'

require 'minitest/spec'
require 'minitest/autorun'

require "openssl"

class MockAPNS
  class Request < Struct.new(:headers, :body)
    def initialize(*)
      super
      self.headers ||= {}
    end
  end

  def self.certificate_with_uid(uid)
    key = OpenSSL::PKey::RSA.new(512)
    name = OpenSSL::X509::Name.parse("/UID=#{uid}/CN=Stubbed APNs: #{uid}")
    cert = OpenSSL::X509::Certificate.new
    cert.subject    = name
    cert.not_before = Time.now
    cert.not_after  = cert.not_before + 3600
    cert.public_key = key.public_key
    cert.sign(key, OpenSSL::Digest::SHA1.new)
    [key, cert]
  end

  attr_reader :requests

  def initialize
    @requests = []

    @context = OpenSSL::SSL::SSLContext.new
    # TODO figure out how to make the cert cerification work.
    #@context.verify_mode = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    @context.key, @context.cert = self.class.certificate_with_uid("com.example.MockAPNS")

    @ssl = OpenSSL::SSL::SSLServer.new(TCPServer.new(0), @context)
  end

  def uri
    URI.parse("https://localhost:#{@ssl.addr[1]}")
  end

  def certificate
    @context.cert
  end

  def run
    @thread = Thread.new do
      loop do
        sock = @ssl.accept
        #puts 'New TCP connection!'

        conn = HTTP2::Server.new
        conn.on(:frame) do |bytes|
          #puts "Writing bytes: #{bytes.unpack("H*").first}"
          sock.write bytes
        end
        #conn.on(:frame_sent) do |frame|
          #puts "Sent frame: #{frame.inspect}"
        #end
        #conn.on(:frame_received) do |frame|
          #puts "Received frame: #{frame.inspect}"
        #end

        conn.on(:stream) do |stream|
          req, buffer = {}, ''
          request = Request.new

          #stream.on(:active) { puts 'client opened new stream' }
          #stream.on(:close)  { puts 'stream closed' }

          stream.on(:headers) do |h|
            request.headers = Hash[*h.flatten]
            #puts "request headers: #{h}"
          end

          stream.on(:data) do |d|
            #puts "payload chunk: <<#{d}>>"
            buffer << d
          end

          stream.on(:half_close) do
            #puts 'client closed its end of the stream'

            request.body = buffer
            @requests << request

            response = nil
            if req[':method'] == 'POST'
              response = "Hello HTTP 2.0! POST payload: #{buffer}"
            else
              response = 'Hello HTTP 2.0! GET request'
            end

            stream.headers({
              ':status' => '200',
              'content-length' => response.bytesize.to_s,
              'content-type' => 'text/plain',
            }, end_stream: false)

            # split response into multiple DATA frames
            stream.data(response.slice!(0, 5), end_stream: false)
            stream.data(response)
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

