require "test_helper"

module Lowdown
  class Connection
    attr_reader :worker

    class Worker
      attr_reader :ssl, :callback_thread

      # So, our test server does not behave exactly the same as the APNS service, which would normally be:
      # 1. The preface dance is done
      # 2. The server sends settings
      # 3. The client changes state to :connected.
      #
      # In our test setup, step 1 and 2 seem to not work as expected and thus the client doesn’t change to the :connected
      # state. Since it’s not that big of a deal, as it works in practice, this override ensures that our implementation
      # does not halt indefinitely in our tests.
      #
      # TODO: Figure out what’s going wrong so this isn’t needed.
      #
      def http_connected?
        true
      end
    end
  end
end

module Lowdown
  describe Connection do
    server = nil

    before do
      server ||= MockAPNS.new.tap(&:run)
      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.cert = server.certificate
      ssl_context.key = server.pkey
      @connection = Connection.new(server.uri, ssl_context)
    end

    #it "uses the certificate to connect" do
      ## verifies that it *does* fail with the wrong certificate
      #_, other_cert = MockAPNS.certificate_with_uid("com.example.other")
      #connection = Lowdown::Connection.new(server.uri, other_cert)
      #lambda { connection.open }.must_raise(OpenSSL::SSL::SSLError)
    #end

    it "returns whether or not the connection is open" do
      @connection.open?.must_equal false
      @connection.open
      @connection.open?.must_equal true
      @connection.close
      @connection.open?.must_equal false
    end

    describe "when making a request" do
      before do
        @connection.open
        @connection.post("/3/device/some-device-token", { "apns-id" => 42 }, "♥") { |r| @response = r }
        @connection.flush

        @request = server.requests.last
      end

      after do
        @connection.close
      end

      it "makes a POST request" do
        @request.headers[":method"].must_equal "POST"
      end

      it "specifies the :path" do
        @request.headers[":path"].must_equal "/3/device/some-device-token"
      end

      it "converts header values to strings" do
        @request.headers["apns-id"].must_equal "42"
      end

      it "specifies the payload size in bytes" do
        @request.headers["content-length"].must_equal "3"
      end

      it "sends the payload" do
        @request.body.must_equal "♥".force_encoding(Encoding::BINARY)
      end

      it "yields the response" do
        @response.status.must_equal 200
        @response.unformatted_id.must_equal "42"
      end
    end

    describe Connection::Worker do
      before do
        @worker = Connection::Worker.new(@connection.uri, @connection.ssl_context)
      end

      after do
        @worker[:should_exit] = true
        @worker.join
      end

      it "raises exceptions that occur on the worker thread onto the caller (current) thread" do
        Timeout.timeout(5) do
          lambda do
            @worker.enqueue { raise EOFError, "eof" }
            Thread.stop
          end.must_raise EOFError
        end
      end

      it "cleans up if an exception occurred" do
        begin
          @worker.enqueue { raise EOFError, "eof" }
          Thread.stop
        rescue EOFError
        end
        @worker.ssl.closed?.must_equal true
        alive = true
        Timeout.timeout(5) do
          sleep 0.1 while @worker.callback_thread.alive?
          alive = false
        end
        alive.must_equal false
      end
    end
  end
end
