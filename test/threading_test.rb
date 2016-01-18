require "test_helper"
require "timeout"

module Lowdown::Threading
  describe Consumer do
    before do
      @consumer = Consumer.new
    end

    after do
      @consumer.kill
    end

    it "initializes with an empty queue and a running thread" do
      @consumer.empty?.must_equal true
      @consumer.alive?.must_equal true
    end

    it "halts the thread when performing a job with an empty queue" do
      lambda do
        Timeout.timeout(0.1) do
          @consumer.send(:perform_job, false)
        end
      end.must_raise Timeout::Error

      # Won’t raise
      Timeout.timeout(0.1) do
        @consumer.send(:perform_job, true)
      end
    end

    it "passes arguments to the job" do
      # don’t let the runloop perform the job
      @consumer.kill
      sleep 0.1 while @consumer.alive?

      yielded = nil
      @consumer.enqueue { |x| yielded = x }
      @consumer.send(:perform_job, false, :ok)
      yielded.must_equal :ok
    end

    it "performs jobs on a different thread" do
      caller_thread = Thread.current
      consumer_thread = nil
      Timeout.timeout(1) do
        @consumer.enqueue do
          sleep 0.1 # ensure the caller thread first stops
          consumer_thread = Thread.current
          caller_thread.run
        end
        Thread.stop
      end
      consumer_thread.wont_equal caller_thread
    end

    it "raises exceptions that occur on the consumer thread onto the caller (current) thread" do
      lambda do
        Timeout.timeout(1) do
          @consumer.enqueue do
            sleep 0.1 # ensure the caller thread first stops
            raise EOFError, "eof"
          end
          Thread.stop
        end
      end.must_raise EOFError
    end

    it "stops the thread if an exception occurred" do
      begin
        @consumer.enqueue do
          sleep 0.1 # ensure the caller thread first stops
          raise EOFError, "eof"
        end
        Thread.stop
      rescue EOFError
      end
      Timeout.timeout(1) do
        # should exit without reaching timeout
        sleep 0.1 while @consumer.alive?
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
