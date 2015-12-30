require "test_helper"

describe Lowdown::Notification do
  it "formats the ID to the canonical 8-4-4-4-12 format" do
    Lowdown::Notification.new(:id => nil).formatted_id.must_equal nil
    Lowdown::Notification.new(:id => 42).formatted_id.must_equal "00000000-0000-0000-0000-000000000042"
    Lowdown::Notification.new(:id => "5682d0d35a9416d877000000").formatted_id.must_equal "00000000-5682-d0d3-5a94-16d877000000"
  end
end
