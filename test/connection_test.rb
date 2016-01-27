require "test_helper"

class MockDelegate
  attr_reader :condition

  def initialize
    @condition = Celluloid::Condition.new
  end

  def handle_apns_response(response, context:)
    @condition.signal(response)
  end
end

module Lowdown
  describe Connection do
    server = nil

    before do
      server ||= MockAPNS.new.tap(&:run)
      @ssl_context = OpenSSL::SSL::SSLContext.new
      @ssl_context.cert = server.certificate
      @ssl_context.key = server.pkey
    end

    after do
      @connection.terminate if @connection.alive?
    end

    it "immediately connects by default" do
      @connection = Connection.new(server.uri, @ssl_context)
      -> { @connection.connected? }.must_eventually_pass
    end

    it "does not try to double connect when calling connect after already connecting at initialization" do
      @connection = Connection.new(server.uri, @ssl_context, true)
      @connection.connect
      @connection.connect
      -> { @connection.connected? }.must_eventually_pass
    end

    describe "with a connection" do
      before do
        @connection = Connection.new(server.uri, @ssl_context, false)
        @connection.connect

        # So, our test server does not behave exactly the same as the APNS service, which would normally be:
        # 1. The preface dance is done
        # 2. The server sends settings
        # 3. The client changes state to :connected.
        #
        # In our test setup, step 1 and 2 seem to not work as expected and thus the client doesn’t change to the
        # :connected state. Since it’s not that big of a deal, as it works in practice, this call ensures that our
        # implementation does not halt indefinitely in our tests.
        #
        # TODO: Figure out what’s going wrong so this isn’t needed.
        #
        @connection.async.send(:change_to_connected_state)

        @delegate = MockDelegate.new
      end

      it "returns whether or not the connection is connected" do
        @connection.connected?.must_equal true
        @connection.disconnect
        @connection.connected?.must_equal false
      end

      describe "concerning the connection life-cycle" do
        it "raises if the service closes the connection" do
          silence_logger do
            @connection.async.post(path: "/3/device/some-device-token",
                                   headers: { "test-close-connection" => "true" },
                                   body: "♥",
                                   delegate: @delegate)
            -> { !@connection.alive? }.must_eventually_pass
          end
        end
      end

      describe "when making a request" do
        before do
          @connection.async.post(path: "/3/device/some-device-token",
                                 headers: { "apns-id" => 42 },
                                 body: "♥",
                                 delegate: @delegate)
          @response = @delegate.condition.wait
          @request = server.requests.last
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
          @response.id.end_with?("42").must_equal true
        end
      end
    end
  end
end

