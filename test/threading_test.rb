require "test_helper"

module Lowdown::Threading
  describe Counter do
    before do
      @counter = Counter.new
    end

    it "initializes with 0" do
      @counter.value.must_equal 0
    end

    it "assigns the value" do
      @counter.value = 42
      @counter.value.must_equal 42
    end

    it "returns whether or not the value is zero" do
      @counter.zero?.must_equal true
      @counter.value = 42
      @counter.zero?.must_equal false
    end

    it "increments the value" do
      @counter.increment!
      @counter.value.must_equal 1
    end

    it "decrements the value" do
      @counter.value = 1
      @counter.decrement!
      @counter.value.must_equal 0
    end
  end
end
