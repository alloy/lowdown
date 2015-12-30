require "test_helper"

class ConnectionMock < Struct.new(:path, :headers, :body)
  def post(path, headers, body)
    self.path = path
    self.headers = headers
    self.body = body
  end
end

describe Lowdown::Client do
  before do
    @key_and_cert = MockAPNS.certificate_with_uid("com.example.MockAPNS")
    @client = Lowdown::Client.new(Lowdown::Client::DEVELOPMENT_URI, @key_and_cert.map(&:to_pem).join("\n"))
  end

  it "configures a connection" do
    @client.connection.uri.must_equal Lowdown::Client::DEVELOPMENT_URI
    @client.connection.ssl_context.key.to_pem.must_equal @key_and_cert.first.to_pem
    @client.connection.ssl_context.cert.to_pem.must_equal @key_and_cert.last.to_pem
  end

  it "extracts the Bundle ID as the default topic from the certificate" do
    @client.default_topic.must_equal "com.example.MockAPNS"
  end

  describe "when sending a notification" do
    before do
      @connection = ConnectionMock.new
      @client.instance_variable_set(:@connection, @connection)

      @notification = Lowdown::Notification.new(
        :payload => { :alert => "Push it real good." },
        :token => "some-device-token",
        :id => 42,
        :expiration => Time.now,
        :priority => 10,
        :topic => "net.artsy.artsy"
      )
    end

    describe "in general" do
      before do
        @client.send_notification(@notification)
      end

      it "sends the payload JSON encoded" do
        payload = { :aps => @notification.payload }
        @connection.body.must_equal payload.to_json
      end

      it "uses the device token in the request path" do
        @connection.path.must_equal "/3/device/some-device-token"
      end

      it "specifies the notification identifier" do
        @connection.headers["apns-id"].must_equal @notification.formatted_id
      end

      it "specifies the expiration time" do
        @connection.headers["apns-expiration"].must_equal @notification.expiration.to_i
      end

      it "specifies the priority" do
        @connection.headers["apns-priority"].must_equal 10
      end

      it "specifies the topic" do
        @connection.headers["apns-topic"].must_equal "net.artsy.artsy"
      end
    end

    describe "when omitting data" do
      before do
        @notification.expiration = nil
        @notification.id = nil
        @notification.priority = nil
        @notification.topic = nil
        @client.send_notification(@notification)
      end

      it "defaults the expiration time to 0" do
        @connection.headers["apns-expiration"].must_equal 0
      end

      it "defaults the topic to the one extracted from the certificate" do
        @connection.headers["apns-topic"].must_equal "com.example.MockAPNS"
      end

      %w{ apns-id apns-priority }.each do |key|
        it "omits the #{key} header" do
          @connection.headers.has_key?(key).must_equal false
        end
      end
    end
  end
end
