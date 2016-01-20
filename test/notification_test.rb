require "test_helper"

module Lowdown
  describe Notification do
    parallelize_me!

    it "assigns a sequential generated ID" do
      id = Notification.generate_id
      Notification.new(:id => nil).id.must_equal(id += 1)
      Notification.new(:id => nil).id.must_equal(id += 1)
    end

    it "formats the ID to the canonical 8-4-4-4-12 format" do
      Notification.new(:id => 42).formatted_id.must_equal "00000000-0000-0000-0000-000000000042"
      Notification.new(:id => "5682d0d35a9416d877000000").formatted_id.must_equal "00000000-5682-d0d3-5a94-16d877000000"
    end

    describe "concerning payload" do
      parallelize_me!

      before do
        @formatted_payload = {
          "aps" => {
            "alert" => "aps",
            "badge" => "aps",
            "sound" => "aps",
            "content-available" => "aps",
            "category" => "aps",
          },
          "url" => "custom",
        }
      end

      it "splits the payload into aps and custom data" do
        notification = Notification.new(:payload => @formatted_payload["aps"].merge("url" => "custom"))
        notification.formatted_payload.must_equal(@formatted_payload)
      end

      it "returns the payload as-is if it's already split" do
        notification = Notification.new(:payload => @formatted_payload)
        notification.formatted_payload.must_equal(@formatted_payload)
      end

      it "does not include entries with `nil` values when splitting data" do
        notification = Notification.new(:payload => { "alert" => "included", "badge" => nil })
        notification.formatted_payload.must_equal("aps" => { "alert" => "included" })
      end
    end
  end
end
