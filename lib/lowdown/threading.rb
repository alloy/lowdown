require "thread"

module Lowdown
  # A collection of internal threading related helpers.
  #
  module Threading
    # A queue of blocks that are to be dispatched onto another thread.
    #
    class DispatchQueue
      def initialize
        @queue = Queue.new
      end

      # Adds a block to the queue.
      #
      # @return [void]
      #
      def dispatch(&block)
        @queue << block
      end

      # @return [Boolean]
      #         whether or not the queue is empty.
      #
      def empty?
        @queue.empty?
      end

      # Performs the number of dispatched blocks that were on the queue at the moment of calling `#drain!`. Unlike
      # performing blocks _until the queue is empty_, this ensures that it doesn’t block the calling thread too long if
      # another thread is dispatching more work at the same time.
      #
      # By default this will let any exceptions bubble up on the main thread or catch and return them on other threads.
      #
      # @param  [Boolean] rescue_exceptions
      #         whether or not to rescue exceptions.
      #
      # @return [Exception, nil]
      #         in case of rescueing exceptions, this returns the exception raised during execution of a block.
      #
      def drain!(rescue_exceptions = (Thread.current != Thread.main))
        @queue.size.times { @queue.pop.call }
        nil
      rescue Exception => exception
        raise unless rescue_exceptions
        exception
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
