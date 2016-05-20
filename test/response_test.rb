require "test_helper"

module Lowdown
  describe Response do
    parallelize_me!

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
      response = Response.new({ ":status" => "400" }, { "reason" => "BadCertificate" }.to_json)
      response.failure_reason.must_equal "BadCertificate"
    end

    it "returns if there was any issue with the token (other than it missing completely)" do
      Response.new(":status" => "200").invalid_token?.must_equal false
      Response.new({ ":status" => "400" }, { "reason" => "BadCertificate" }.to_json).invalid_token?.must_equal false

      [%w(410 Unregistered), %w(400 BadDeviceToken), %w(400 DeviceTokenNotForTopic)].each do |status, reason|
        Response.new({ ":status" => status }, { "reason" => reason }.to_json).invalid_token?.must_equal true
      end
    end

    describe "concerning an inactive token" do
      parallelize_me!

      before do
        @timestamp = Time.now
        @response = Response.new({ ":status" => "410" }, { "timestamp" => (@timestamp.to_i * 1000).to_s }.to_json)
      end

      it "returns that it concerns an inactive token" do
        @response.inactive_token?.must_equal true
        Response.new(":status" => "200").inactive_token?.must_equal false
      end

      it "returns the time at which APNS for the last time verified that the token is invalid" do
        @response.activity_last_checked_at.to_i.must_equal @timestamp.to_i
      end
    end
  end
end

