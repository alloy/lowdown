require "lowdown/response"

module Lowdown
  class Connection
    class Mock
      Request = Struct.new(:path, :headers, :body, :response)

      attr_reader :requests, :responses

      def initialize(responses = [])
        @responses = responses
        @requests = []
      end

      def requests_as_notifications(unformatted_id_length = nil)
        @requests.map do |request|
          headers = request.headers
          hash = {
            :token => File.basename(request.path),
            :id => request.response.unformatted_id(unformatted_id_length),
            :payload => JSON.parse(request.body),
            :topic => headers["apns-topic"]
          }
          hash[:expiration] = Time.at(headers["apns-expiration"].to_i) if headers["apns-expiration"]
          hash[:priority] = headers["apns-priority"].to_i if headers["apns-priority"]
          Notification.new(hash)
        end
      end

      def post(path, headers, body)
        response = @responses.shift || Response.new(":status" => "200", "apns-id" => (headers["apns-id"] || generate_id))
        @requests << Request.new(path, headers, body, response)
        yield response
      end

      def open
        @open = true
      end

      def close
        @open = false
      end

      def open?
        !!@open
      end

      private

      def generate_id
        @counter ||= 0
        @counter += 1
        Notification.new(:id => @counter).formatted_id
      end
    end
  end
end
