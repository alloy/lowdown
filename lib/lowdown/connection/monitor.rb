# frozen_string_literal: true

require "celluloid/current"

module Lowdown
  class Connection
    module Monitor
      # The normal Celluloid::Future implementation expects an object that responds to `value`, when assigning the value
      # via `#signal`:
      #
      # 1. https://github.com/celluloid/celluloid/blob/bb282f826c275c0d60d9591c1bb5b08798799cbe/lib/celluloid/future.rb#L106
      # 2. https://github.com/celluloid/celluloid/blob/bb282f826c275c0d60d9591c1bb5b08798799cbe/lib/celluloid/future.rb#L96
      #
      # Besides that, this class provides a few more conveniences related to how we use this future.
      #
      class Condition < Celluloid::Future
        Result = Struct.new(:value)

        # Only signal once.
        #
        def signal(value = nil)
          super(Result.new(value)) unless ready?
        end

        alias_method :wait, :value
      end

      # @!group Overrides

      def initialize(*)
        super
        @lowdown_crash_conditions_mutex = Mutex.new
        @lowdown_crash_conditions = []
      end

      # Send the exception to each of our conditions, to signal that an exception occurred on one of the actors in the
      # pool.
      #
      # @param  [Actor] actor
      # @param  [Exception] reason
      # @return [void]
      #
      def __crash_handler__(actor, reason)
        if reason # is nil if the actor exits normally
          @lowdown_crash_conditions_mutex.synchronize do
            @lowdown_crash_conditions.each do |condition|
              condition.signal(reason)
            end
          end
        end
        super
      end

      # @!group Crash condition registration

      # Adds a condition to the list of conditions to be notified when an actors dies because of an unhandled exception.
      #
      # @param  [Condition] condition
      # @return [void]
      #
      def __register_lowdown_crash_condition__(condition)
        @lowdown_crash_conditions_mutex.synchronize do
          @lowdown_crash_conditions << condition
        end
      end

      # Removes a condition from the list of conditions that get notified when an actor dies because of an unhandled
      # exception.
      #
      # @param  [Condition] condition
      # @return [void]
      #
      def __deregister_lowdown_crash_condition__(condition)
        @lowdown_crash_conditions_mutex.synchronize do
          @lowdown_crash_conditions.delete(condition)
        end
      end
    end

    # Prepend to ensure our overrides are called first.
    Celluloid::Supervision::Container::Pool.send(:prepend, Monitor)
  end
end

