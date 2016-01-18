require "thread"

module Lowdown
  # A collection of internal threading related helpers.
  #
  module Threading
    # This class performs jobs on a private thread, provides lifecycle callbacks, and sends exceptions onto its parent
    # thread.
    #
    class Consumer
      # @param  [Thread::Queue] queue
      #         a queue instance. Provide a `Thread::SizedQueue` if you want queue of a max size.
      #
      # @param  [Thread] parent_thread
      #         the thread to send exceptions to.
      #
      def initialize(queue: Thread::Queue.new, parent_thread: Thread.current)
        @queue, @parent_thread = queue, parent_thread
        @thread = Thread.new(&method(:main))
      end

      # Schedules a job to be performed.
      #
      # @return [void]
      #
      def enqueue(&job)
        queue << job
      end

      # Kills the private thread.
      #
      # @return [void]
      #
      def kill
        thread.kill
      end

      # @return [Boolean]
      #         whether or not the private thread is still alive.
      #
      def alive?
        thread.alive?
      end

      # @return [Boolean]
      #         whether or not there are any scheduled jobs left in the queue.
      #
      def empty?
        queue.empty?
      end

      protected

      # @return [Thread]
      #         the private thread.
      #
      attr_reader :thread

      # @return [Thread]
      #         the thread to send exceptions to.
      #
      attr_reader :parent_thread

      # @return [Thread::Queue]
      #         the jobs queue.
      #
      attr_reader :queue

      # This represents the full lifecycle of the consumer thread. It performs the individual events, catches uncaught
      # exceptions and sends those to the parent thread, and performs cleanup.
      #
      # Subclasses should override the individual events.
      #
      # @note This method is ran on the private thread.
      #
      # @return [void]
      #
      def main
        pre_runloop
        runloop
      rescue Exception => exception
        parent_thread.raise(exception)
      ensure
        post_runloop
      end

      # Ran _before_ any jobs are performed.
      #
      # @note (see #main)
      #
      # @return [void]
      #
      def pre_runloop
      end

      # The loop that performs scheduled jobs.
      #
      # @note (see #main)
      #
      # @return [void]
      #
      def runloop
        loop { perform_job(non_block: false) }
      end

      # Ran when the thread is killed or an uncaught exception occurred.
      #
      # This kills the consumer thread, which means that any cleanup you need to perform should be done *before* calling
      # this `super` implementation.
      #
      # @note (see #main)
      #
      # @return [void]
      #
      def post_runloop
        thread.kill
      end

      # @param  [Boolean] non_block
      #         whether or not the thread should be halted if there are no jobs to perform.
      #
      # @param  [Array<Object>] arguments
      #         arguments that should be passed to the invoked job.
      #
      # @return [void]
      #
      def perform_job(non_block:, arguments: nil)
        queue.pop(non_block).call(*arguments)
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
