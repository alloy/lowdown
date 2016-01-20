require "test_helper"
require "lowdown/mock"

require "weakref"

module Lowdown
  describe Client do
    describe "concerning initialization" do
      parallelize_me!

      before do
        @certificate = Mock.certificate("com.example.MockAPNS")
        @uri = Client::DEVELOPMENT_URI
      end

      it "configures a connection to the production environment" do
        @certificate.certificate.extensions = [OpenSSL::X509::Extension.new(Certificate::PRODUCTION_ENV_EXTENSION, "..")]
        client = Client.production(true, @certificate)
        client.connection.uri.must_equal Client::PRODUCTION_URI
      end

      it "configures a connection to the development environment" do
        @certificate.certificate.extensions = [OpenSSL::X509::Extension.new(Certificate::DEVELOPMENT_ENV_EXTENSION, "..")]
        client = Client.production(false, @certificate)
        client.connection.uri.must_equal Client::DEVELOPMENT_URI
      end

      it "configures a connection with the given uri" do
        client = Client.client(@uri, @certificate)
        client.connection.uri.must_equal @uri
      end

      it "configures a connection with PEM data" do
        client = Client.client(@uri, @certificate.to_pem)
        client.connection.ssl_context.key.to_pem.must_equal @certificate.key.to_pem
        client.connection.ssl_context.cert.to_pem.must_equal @certificate.certificate.to_pem
      end

      it "has no default topic if the certificate is not a Universal Certificate" do
        @certificate.certificate.extensions = []
        client = Client.client(@uri, @certificate)
        client.default_topic.must_equal nil
      end

      it "uses the app bundle ID as the default topic in case of a Universal Certificate" do
        client = Client.client(@uri, @certificate)
        client.default_topic.must_equal "com.example.MockAPNS"
      end

      it "configures the connection actor to be terminated when the client is garbage collected" do
        client = WeakRef.new(Client.client(@uri, @certificate))
        connection = client.connection
        connection.alive?.must_equal true
        GC.start
        connection.alive?.must_equal false
      end

      it "does not indefinitely retain the client (paranoia test for the connection finalizer)" do
        client = WeakRef.new(Client.client(@uri, @certificate))
        (!!client.weakref_alive?).must_equal true
        GC.start
        (!!client.weakref_alive?).must_equal false
      end
    end

    describe "when initialized" do
      parallelize_me!

      before do
        @connection = Mock::Connection.new
        @client = Client.new(@connection, "com.example.MockAPNS")
      end

      it "opens the connection for the duration of the block and then closes it" do
        opened_connection = false
        @client.connect { opened_connection = @client.connection.open? }
        opened_connection.must_equal true
        @client.connection.open?.must_equal false
      end

      it "yields a request group" do
        yielded_group = nil
        @client.connect { |group| yielded_group = group }
        yielded_group.class.must_equal Client::RequestGroup
      end

      describe "when sending a notification" do
        parallelize_me!

        before do
          @notification = Notification.new(
            :payload => { :alert => "Push it real good.", :url => "http://example/custom-attribute" },
            :token => "some-device-token",
            :id => 42,
            :expiration => Time.now,
            :priority => 10,
            :topic => "com.example.MockAPNS.voip"
          )
        end

        it "yields the response and context on completion" do
          yielded_response = yielded_context = nil
          @client.connect do |group|
            group.send_notification(@notification, context: :ok) do |response, context|
              yielded_response = response
              yielded_context = context
            end
          end
          yielded_response.id.end_with?("42").must_equal true
          yielded_context.must_equal :ok
        end

        describe "in general" do
          parallelize_me!

          before do
            @client.connect do |group|
              group.send_notification(@notification) {}
            end
            @request = @connection.requests.last
          end

          it "sends the formatted payload JSON encoded" do
            @request.body.must_equal @notification.formatted_payload.to_json
          end

          it "uses the device token in the request path" do
            @request.path.must_equal "/3/device/some-device-token"
          end

          it "specifies the notification identifier" do
            @request.headers["apns-id"].must_equal @notification.formatted_id
          end

          it "specifies the expiration time" do
            @request.headers["apns-expiration"].must_equal @notification.expiration.to_i
          end

          it "specifies the priority" do
            @request.headers["apns-priority"].must_equal 10
          end

          it "specifies the topic" do
            @request.headers["apns-topic"].must_equal "com.example.MockAPNS.voip"
          end
        end

        describe "when omitting data" do
          parallelize_me!

          before do
            @notification.expiration = nil
            @notification.id = nil
            @notification.priority = nil
            @notification.topic = nil
            @client.connect do |group|
              group.send_notification(@notification) {}
            end
            @request = @connection.requests.last
          end

          it "defaults the expiration time to 0" do
            @request.headers["apns-expiration"].must_equal 0
          end

          it "defaults the topic to the one extracted from the certificate" do
            @request.headers["apns-topic"].must_equal "com.example.MockAPNS"
          end

          it "omits the apns-priority header" do
            @request.headers.has_key?("apns-priority").must_equal false
          end
        end
      end
    end
  end
end
