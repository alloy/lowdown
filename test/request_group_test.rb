require "test_helper"
require "lowdown/mock"

module Lowdown
  describe Client::RequestGroup do
    before do
      @connection = Mock::Connection.new
      @client = Client.new(connection: @connection, default_topic: "com.example.MockAPNS")
      @client.connect

      @condition = Connection::Monitor::Condition.new
      @group = Client::RequestGroup.new(@client, @condition)

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

    it "performs a message callback" do
      performed = false
      delegate = Object.new
      delegate.define_singleton_method(:handle_apns_response) do |_, __|
        sleep 0.1 # test that flush works
        performed = true
      end
      @group.send_notification(@notification, delegate: delegate)
      @condition.wait(1)
      performed.must_equal true
    end

    it "performs a block callback" do
      performed = false
      @group.send_notification(@notification) do
        sleep 0.1 # test that flush works
        performed = true
      end
      @condition.wait(1)
      performed.must_equal true
    end

    it "performs the callback on a different thread" do
      thread = nil
      @group.send_notification(@notification) do
        thread = Thread.current
      end
      @condition.wait(1)
      thread.wont_equal nil
      thread.wont_equal Thread.current
    end

    it "yields the response and context" do
      yielded_response = yielded_context = nil
      @group.send_notification(@notification, context: :ok) do |response, context|
        yielded_response = response
        yielded_context = context
      end
      @condition.wait(1)
      yielded_response.id.end_with?("42").must_equal true
      yielded_context.must_equal :ok
    end

    it "passes an async proxy of the callbacks object as the delegate" do
      @group.send_notification(@notification) {}
      @connection.requests.last.delegate.class.must_equal Celluloid::Proxy::Async
    end
  end
end

