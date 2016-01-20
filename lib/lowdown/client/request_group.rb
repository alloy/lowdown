require "celluloid/current"

module Lowdown
  class Client
    class RequestGroup
      attr_reader :callbacks

      def initialize(client)
        @client = client
        @callbacks = Callbacks.new
      end

      def send_notification(notification, context: nil, &callback)
        @callbacks.add(notification.formatted_id, callback)
        @client.send_notification(notification, delegate: @callbacks.async, context: context)
      end

      def terminate
        @callbacks.terminate
      end

      def flush
        # Don’t block if all notifications are already delivered.
        @callbacks.condition.wait unless @callbacks.empty?
      end

      class Callbacks
        include Celluloid

        attr_reader :condition

        def initialize
          @callbacks = {}
          @condition = Celluloid::Condition.new
        end

        def empty?
          @callbacks.empty?
        end

        def add(notification_id, callback)
          raise ArgumentError, "A notification ID is required." unless notification_id
          @callbacks[notification_id] = callback
        end

        def handle_apns_response(response, context:)
          @callbacks.delete(response.id).call(response, context)
        ensure
          @condition.signal if @callbacks.empty?
        end
      end
    end
  end
end

