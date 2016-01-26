require "test_helper"
require "lowdown/mock"

module Lowdown
  describe Client::RequestGroup do
    before do
      @connection = Mock::Connection.new
      @client = Client.new(connection: @connection, default_topic: "com.example.MockAPNS")
      @client.connect

      @group = Client::RequestGroup.new(@client)

      @notification = Notification.new(
        :payload => { :alert => "Push it real good.", :url => "http://example/custom-attribute" },
        :token => "some-device-token",
        :id => 42,
        :expiration => Time.now,
        :priority => 10,
        :topic => "com.example.MockAPNS.voip"
      )
    end

    after do
      @group.terminate
    end

    it "does not halt when flushing an empty group" do
      Timeout.timeout(1) { @group.flush } # Should not raise
    end

    it "performs the callback" do
      performed = false
      @group.send_notification(@notification) do
        sleep 0.1 # test that flush works
        performed = true
      end
      @group.flush
      performed.must_equal true
    end

    it "performs the callback on a different thread" do
      thread = nil
      @group.send_notification(@notification) do
        thread = Thread.current
      end
      @group.flush
      thread.wont_equal nil
      thread.wont_equal Thread.current
    end

    it "yields the response and context" do
      yielded_response = yielded_context = nil
      @group.send_notification(@notification, context: :ok) do |response, context|
        yielded_response = response
        yielded_context = context
      end
      @group.flush
      yielded_response.id.end_with?("42").must_equal true
      yielded_context.must_equal :ok
    end

    it "passes an async proxy of the callbacks object as the delegate" do
      @group.send_notification(@notification) {}
      @connection.requests.last.delegate.class.must_equal Celluloid::Proxy::Async
    end
  end
end
