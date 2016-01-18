require "thread"
require "forwardable"

module Lowdown
  # A collection of internal threading related helpers.
  #
  module Threading
    class Consumer
      extend Forwardable

      def_delegators :@thread, :kill, :alive?
      def_delegators :@queue, :empty?

      def initialize(queue: Thread::Queue.new, parent_thread: Thread.current)
        @queue, @parent_thread = queue, parent_thread
        @thread = Thread.new(&method(:main))
      end

      def enqueue(&job)
        queue << job
      end

      protected

      attr_reader :thread, :parent_thread, :queue

      def main
        pre_runloop
        runloop
      rescue Exception => exception
        parent_thread.raise(exception)
      ensure
        post_runloop
      end

      def pre_runloop
      end

      def runloop
        loop { perform_job(false) }
      end

      # This kills the consumer thread, which means that any cleanup you need to perform should be done *before* calling
      # this `super` implementation.
      #
      def post_runloop
        thread.kill
      end

      # @return [void]
      #
      def perform_job(non_block, *args)
        queue.pop(non_block).call(*args)
      rescue ThreadError
      end
    end

    # A simple thread-safe counter.
    #
    class Counter
      # @param  [Integer] value
      #         the initial count.
      #
      def initialize(value = 0)
        @value = value
        @mutex = Mutex.new
      end

      # @return [Integer]
      #         the current count.
      #
      def value
        value = nil
        @mutex.synchronize { value = @value }
        value
      end

      # @return [Boolean]
      #         whether or not the current count is zero.
      #
      def zero?
        value.zero?
      end

      # @param  [Integer] value
      #         the new count.
      #
      # @return [Integer]
      #         the input value.
      #
      def value=(value)
        @mutex.synchronize { @value = value }
        value
      end

      # Increments the current count.
      #
      # @return [void]
      #
      def increment!
        @mutex.synchronize { @value += 1 }
      end

      # Decrements the current count.
      #
      # @return [void]
      #
      def decrement!
        @mutex.synchronize { @value -= 1 }
      end
    end
  end
end
