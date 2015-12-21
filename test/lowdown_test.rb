require "test_helper"

describe Lowdown::Connection do
  server = nil

  before do
    server ||= MockAPNS.new.tap(&:run)
    @connection = Lowdown::Connection.new(server.uri, server.certificate)
  end

  #it "uses the certificate to connect" do
    ## verifies that it *does* fail with the wrong certificate
    #_, other_cert = MockAPNS.certificate_with_uid("com.example.other")
    #connection = Lowdown::Connection.new(server.uri, other_cert)
    #lambda { connection.open }.must_raise(OpenSSL::SSL::SSLError)
  #end

  describe "when making a request" do
    before do
      @notification = Lowdown::Notification.new({
        :payload => { "alert" => "Here’s the low-down…" },
        :token => "some-device-token",
        :id => 42,
        :expiration => Time.now,
        :priority => 10,
        :topic => "net.artsy.artsy"
      })

      @connection.open
      @connection.post(@notification)
      @connection.flush

      @request = server.requests.last
    end

    after do
      @connection.close
    end

    it "sends the payload JSON encoded" do
      JSON.parse(@request.body).must_equal @notification.payload
    end

    it "makes a POST request" do
      @request.headers[":method"].must_equal "POST"
    end

    it "uses the device token in the request path" do
      @request.headers[":path"].must_equal "/3/device/some-device-token"
    end

    it "specifies the payload size" do
      content_length = @notification.payload.to_json.bytesize.to_s
      @request.headers["content-length"].must_equal content_length
    end

    it "specifies the notification identifier" do
      @request.headers["apns-id"].must_equal "42"
    end

    it "specifies the expiration time" do
      @request.headers["apns-expiration"].must_equal @notification.expiration.to_i.to_s
    end

    it "defaults the expiration time to 0" do
      @notification.expiration = nil

      @connection.post(@notification)
      @connection.flush

      request = server.requests.last
      request.headers["apns-expiration"].must_equal "0"
    end

    it "specifies the priority" do
      @request.headers["apns-priority"].must_equal "10"
    end

    it "specifies the topic" do
      @request.headers["apns-topic"].must_equal "net.artsy.artsy"
    end
  end
end

#describe Lowdown::Notification do
#end

#describe Lowdown::Client do
#end
