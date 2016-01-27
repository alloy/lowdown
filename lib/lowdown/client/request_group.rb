require "celluloid/current"

module Lowdown
  class Client
    # Implements the {Connection::DelegateProtocol} to provide a more traditional blocks-based callback mechanism.
    #
    # It proxies requests to a client, stores the request callbacks, and performs those once a response is available.
    #
    class RequestGroup
      attr_reader :callbacks

      def initialize(client, condition)
        @client = client
        @callbacks = Callbacks.new(condition)
      end

      def send_notification(notification, context: nil, &callback)
        return unless @callbacks.alive?
        @callbacks.add(notification.formatted_id, callback)
        @client.send_notification(notification, delegate: @callbacks.async, context: context)
      end

      def empty?
        @callbacks.empty?
      end

      def terminate
        @callbacks.terminate if @callbacks.alive?
      end

      class Callbacks
        include Celluloid

        def initialize(condition)
          @callbacks = {}
          @condition = condition
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

