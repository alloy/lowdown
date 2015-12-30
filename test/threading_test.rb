require "test_helper"

module Lowdown::Threading
  describe DispatchQueue do
    before do
      @queue = DispatchQueue.new
    end

    it "returns whether or not there are any stored blocks" do
      @queue.empty?.must_equal true
      @queue.dispatch {}
      @queue.empty?.must_equal false
      @queue.drain!
      @queue.empty?.must_equal true
    end

    it "performs the stored blocks when drained" do
      i = 0
      @queue.dispatch { i += 1 }
      @queue.dispatch { i += 2 }

      i.must_equal 0
      @queue.drain!
      i.must_equal 3
    end

    it "only performs the blocks stored when starting draining" do
      called_expected_block = called_unexpected_block = false

      @queue.dispatch do
        called_expected_block = true
        # This is to make sure that the unexpected block is added to the queue before drain! is finished.
        # If drain! were implemented wrong and would keep draining until the internal queue is empty, then this `sleep`
        # call wouldn’t make a difference.
        sleep 1
      end

      thread = Thread.new(@queue) { |q| q.drain! }
      # Give thread a bit of startup time.
      sleep 0.5

      @queue.dispatch { called_unexpected_block = true }
      thread.join

      called_expected_block.must_equal true
      called_unexpected_block.must_equal false
      @queue.empty?.must_equal false
    end

    describe "concerning exceptions" do
      before do
        @exception = ArgumentError.new("some exception")
        @queue.dispatch { raise @exception }
      end

      it "by default does *not* rescue exceptions on the main thread" do
        lambda { @queue.drain! }.must_raise ArgumentError
      end

      it "by default rescues exceptions on threads other than the main thread" do
        rescued_exception = nil
        Thread.new(@queue) { |q| rescued_exception = q.drain! }.join
        rescued_exception.must_equal @exception
      end
    end
  end

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
