require "test_helper"

module Lowdown
  describe Response do
    it "returns the HTTP status code" do
      Response.new(":status" => "200").status.must_equal 200
    end

    it "returns wheher or not the response status indicates success" do
      Response.new(":status" => "200").success?.must_equal true
      Response.new(":status" => "410").success?.must_equal false
    end

    it "returns a message for the status code" do
      Response.new(":status" => "200").message.must_equal "Success"
      Response.new(":status" => "400").message.must_equal "Bad request"
    end

    it "returns the reason for the failed request" do
      response = Response.new({ ":status" => "400" }, { "reason" => "BadDeviceToken" }.to_json)
      response.failure_reason.must_equal "BadDeviceToken"
    end

    describe "concerning an invalid token" do
      before do
        @timestamp = Time.now
        @response = Response.new({ ":status" => "410" }, { "timestamp" => @timestamp.to_i.to_s }.to_json)
      end

      it "returns that it concerns an invalid token" do
        @response.invalid_token?.must_equal true
        Response.new(":status" => "200").invalid_token?.must_equal false
      end

      it "returns the time at which APNS for the last time verified that the token is invalid" do
        @response.validity_last_checked_at.to_i.must_equal @timestamp.to_i
      end
    end

    describe "#unformatted_id" do
      it "unformats the ID, but always as string" do
        [42, "5682d0d35a9416d877000000"].each do |id|
          formatted_id = Notification.new(:id => id).formatted_id
          Response.new("apns-id" => formatted_id).unformatted_id.must_equal id.to_s
        end
      end

      it "takes an optional expected ID length" do
        formatted_id = Notification.new(:id => 42).formatted_id
        Response.new("apns-id" => formatted_id).unformatted_id(4).must_equal "0042"
      end
    end
  end
end

