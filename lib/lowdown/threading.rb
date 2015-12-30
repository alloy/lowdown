require "thread"

module Lowdown
  module Threading
    class DispatchQueue
      def initialize
        @queue = Queue.new
      end

      def dispatch(&block)
        @queue << block
      end

      def empty?
        @queue.empty?
      end

      # Performs the number of dispatched blocks that were on the queue at the moment of calling #drain!. Unlike
      # performing blocks _until the queue is empty_, this ensures that it doesn’t block the calling thread too long if
      # another thread is dispatching more work at the same time.
      #
      # By default this will let any exceptions bubble up on the main thread or catch and return them on other threads.
      #
      def drain!(rescue_exceptions = (Thread.current != Thread.main))
        @queue.size.times { @queue.pop.call }
        nil
      rescue Exception => exception
        raise unless rescue_exceptions
        exception
      end
    end

    class Counter
      def initialize(value = 0)
        @value = value
        @mutex = Mutex.new
      end

      def value
        value = nil
        @mutex.synchronize { value = @value }
        value
      end

      def zero?
        value.zero?
      end

      def value=(value)
        @mutex.synchronize { @value = value }
        value
      end

      def increment!
        @mutex.synchronize { @value += 1 }
      end

      def decrement!
        @mutex.synchronize { @value -= 1 }
      end
    end
  end
end
