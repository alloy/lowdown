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

      def drain!
        @queue.pop.call until empty?
      end
    end

    class Counter
      def initialize(value = 0)
        @value = value
        @lock = Mutex.new
      end

      def value
        value = nil
        @lock.synchronize { value = @value }
        value
      end

      def zero?
        value.zero?
      end

      def increase!
        @lock.synchronize { @value += 1 }
      end

      def decrease!
        @lock.synchronize { @value -= 1 }
      end
    end
  end
end
