require "thread"

module Lowdown
  # A collection of internal threading related helpers.
  #
  module Threading
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
