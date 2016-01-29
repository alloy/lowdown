require "celluloid/current"

module Lowdown
  class Client
    # Implements the {Connection::DelegateProtocol} to provide a way to group requests and hal the caller thread while
    # waiting for the responses to come in. In addition to the regular delegate message based callbacks, it also allows
    # for a more traditional blocks-based callback mechanism.
    #
    # @note These callbacks are executed on a separate thread, so be aware about this when accessing shared resources
    #       from a block callback.
    #
    class RequestGroup
      attr_reader :callbacks

      def initialize(client, condition)
        @client = client
        @callbacks = Callbacks.new(condition)
      end

      def send_notification(notification, delegate: nil, context: nil, &block)
        return unless @callbacks.alive?
        if (block.nil? && delegate.nil?) || (block && delegate)
          raise ArgumentError, "Either a delegate object or a block should be provided."
        end
        @callbacks.add(notification.formatted_id, block || delegate)
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
          callback = @callbacks.delete(response.id)
          if callback.is_a?(Proc)
            callback.call(response, context)
          else
            callback.send(:handle_apns_response, response, context: context)
          end
        ensure
          @condition.signal if @callbacks.empty?
        end
      end
    end
  end
end

