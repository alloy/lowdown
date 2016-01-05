require "lowdown/certificate"
require "lowdown/client"
require "lowdown/response"

module Lowdown
  module Mock
    def self.ssl_certificate_and_key(app_bundle_id)
      key = OpenSSL::PKey::RSA.new(1024)
      name = OpenSSL::X509::Name.parse("/UID=#{app_bundle_id}/CN=Stubbed APNS Certificate: #{app_bundle_id}")
      cert = OpenSSL::X509::Certificate.new
      cert.subject    = name
      cert.not_before = Time.now
      cert.not_after  = cert.not_before + 3600
      cert.public_key = key.public_key
      cert.sign(key, OpenSSL::Digest::SHA1.new)

      # Make it a Universal Certificate
      ext_name = Lowdown::Certificate::UNIVERSAL_CERTIFICATE_EXTENSION
      cert.extensions = [OpenSSL::X509::Extension.new(ext_name, "0d..#{app_bundle_id}0...app")]

      [cert, key]
    end

    def self.certificate(app_bundle_id)
      Certificate.new(*ssl_certificate_and_key(app_bundle_id))
    end

    def self.client(uri: nil, app_bundle_id: "com.example.MockApp")
      certificate = certificate(app_bundle_id)
      connection = Connection.new(uri: uri, ssl_context: certificate.ssl_context)
      Client.client_with_connection(connection, certificate)
    end

    class Connection
      Request = Struct.new(:path, :headers, :body, :response)

      # Mock API
      attr_reader :requests, :responses

      # Real API
      attr_reader :uri, :ssl_context

      def initialize(uri: nil, ssl_context: nil)
        @uri, @ssl_context = uri, ssl_context
        @responses = []
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
