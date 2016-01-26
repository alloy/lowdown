require "celluloid/current"

module Lowdown
  class Connection
    # Monitors a connection, or a pool of connections, for exceptions and, if any, raises them on the caller thread.
    #
    class Monitor
      def self.monitor(connection)
        new(connection, Thread.current)
      end

      include Celluloid
      trap_exit :connection_crashed

      def initialize(connection, caller_thread)
        @caller_thread = caller_thread
        if connection.respond_to?(:actors)
          connection.actors.each(&method(:monitor_connection))
        else
          monitor_connection(connection)
        end
      end

      def monitor_connection(connection)
        link connection
      end

      def connection_crashed(connection, exception)
        @caller_thread.raise(exception) if exception
      end
    end
  end
end
