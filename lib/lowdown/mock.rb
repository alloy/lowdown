require "lowdown/certificate"
require "lowdown/client"
require "lowdown/response"

module Lowdown
  # Provides a collection of test helpers.
  #
  # This file is not loaded by default.
  #
  module Mock
    # Generates a self-signed Universal Certificate.
    #
    # @param  [String] app_bundle_id
    #         the App ID / app Bundle ID to encode into the certificate.
    #
    # @return [Array<OpenSSL::X509::Certificate, OpenSSL::PKey::RSA>]
    #         the self-signed certificate and private key.
    #
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

    # Generates a Certificate configured with a self-signed Universal Certificate.
    #
    # @param  (see Mock.ssl_certificate_and_key)
    #
    # @return [Certificate]
    #         a Certificate configured with a self-signed certificate/key pair.
    #
    def self.certificate(app_bundle_id)
      Certificate.new(*ssl_certificate_and_key(app_bundle_id))
    end

    # Generates a Client with a mock {Connection} and a self-signed Universal Certificate.
    #
    # @param  [URI, String] uri
    #         the details to connect to the APN service.
    #
    # @param  [String] app_bundle_id
    #         the App ID / app Bundle ID to encode into the certificate.
    #
    # @return [Client]
    #         a Client configured with the `uri` and a self-signed certificate that has the `app_bundle_id` encoded.
    #
    def self.client(uri: nil, app_bundle_id: "com.example.MockApp")
      certificate = certificate(app_bundle_id)
      connection = Connection.new(uri: uri, ssl_context: certificate.ssl_context)
      Client.client_with_connection(connection, certificate)
    end

    # A mock object that can be used instead of a real Connection object.
    #
    class Connection
      # Represents a recorded request.
      #
      Request = Struct.new(:path, :headers, :body, :response, :delegate, :context)

      # @!group Mock API: Instance Attribute Summary

      # @return [Array<Request>]
      #         a list of requests that have been made in order.
      #
      attr_reader :requests

      # @return [Array<Response>]
      #         a list of stubbed responses to return in order.
      #
      attr_reader :responses

      # @!group Mock API: Instance Method Summary

      # @param (see Lowdown::Connection#initialize)
      #
      def initialize(uri: nil, ssl_context: nil)
        @uri, @ssl_context = uri, ssl_context
        @responses = []
        @requests = []
      end

      # @return [Array<Notification>]
      #         returns the recorded requests as Notification objects.
      #
      def requests_as_notifications
        @requests.map do |request|
          headers = request.headers
          hash = {
            :token => File.basename(request.path),
            :id => request.response.id,
            :payload => JSON.parse(request.body),
            :topic => headers["apns-topic"]
          }
          hash[:expiration] = Time.at(headers["apns-expiration"].to_i) if headers["apns-expiration"]
          hash[:priority] = headers["apns-priority"].to_i if headers["apns-priority"]
          Notification.new(hash)
        end
      end

      # @!group Real API: Instance Attribute Summary

      # @return (see Lowdown::Connection#uri)
      #
      attr_reader :uri

      # @return (see Lowdown::Connection#ssl_context)
      #
      attr_reader :ssl_context

      # @!group Celluloid API

      def async
        self
      end

      # @!group Real API: Instance Method Summary

      # Yields stubbed {#responses} or if none are available defaults to success responses. It does this on a different
      # thread, just like the real API does.
      #
      # To make the connection simulate being closed from the other end, specify the `test-close-connection` header.
      #
      # @param (see Lowdown::Connection#post)
      # @yield (see Lowdown::Connection#post)
      # @yieldparam (see Lowdown::Connection#post)
      # @return (see Lowdown::Connection#post)
      #
      def post(path:, headers:, body:, delegate:, context: nil)
        raise "First open the connection." unless @connected

        unless headers["test-close-connection"]
          response = @responses.shift || Response.new(":status" => "200", "apns-id" => headers["apns-id"])
        end
        @requests << Request.new(path, headers, body, response, delegate, context)

        raise EOFError, "Stubbed EOF" if headers["test-close-connection"]

        delegate.handle_apns_response(response, context: context)
      end

      # Changes {#connected?} to return `true`.
      #
      # @return [void]
      #
      def connect
        @connected = true
      end

      # Changes {#connected?} to return `false`.
      #
      # @return [void]
      #
      def disconnect
        @connected = false
      end

      # @return (see Lowdown::Connection#connected?)
      #
      def connected?
        !!@connected
      end
    end
  end
end
