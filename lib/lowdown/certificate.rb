# frozen_string_literal: true
require "openssl"

module Lowdown
  # This class is a wrapper around a certificate/key pair that returns values used by Lowdown.
  #
  class Certificate
    # @!group Constructor Summary

    # @param  [Certificate, String] certificate_or_data
    #         a configured Certificate or PEM data to construct a Certificate from.
    #
    # @return [Certificate]
    #         either the originally passed in Certificate or a new Certificate.
    #
    def self.certificate(certificate_or_data)
      if certificate_or_data.is_a?(Certificate)
        certificate_or_data
      else
        from_pem_data(certificate_or_data)
      end
    end

    # A convenience method that initializes a Certificate from PEM data.
    #
    # @param  [String] data
    #         the PEM encoded certificate/key pair data.
    #
    # @param  [String] passphrase
    #         a passphrase required to decrypt the PEM data.
    #
    # @return (see Certificate#initialize)
    #
    def self.from_pem_data(data, passphrase = nil)
      key = OpenSSL::PKey::RSA.new(data, passphrase)
      certificate = OpenSSL::X509::Certificate.new(data)
      new(certificate, key)
    end

    # @param  [OpenSSL::X509::Certificate] certificate
    #         the Apple Push Notification certificate.
    #
    # @param  [OpenSSL::PKey::RSA] key
    #         the private key that belongs to the certificate.
    #
    def initialize(certificate, key = nil)
      @key, @certificate = key, certificate
    end

    # @!group Instance Attribute Summary

    # @return [OpenSSL::X509::Certificate]
    #         the Apple Push Notification certificate.
    #
    attr_reader :certificate

    # @return [OpenSSL::PKey::RSA, nil]
    #         the private key that belongs to the certificate.
    #
    attr_reader :key

    # @!group Instance Method Summary

    # @return [String]
    #         the certificate/key pair encoded as PEM data. Only used for testing.
    #
    def to_pem
      [@key, @certificate].compact.map(&:to_pem).join("\n")
    end

    # @return [OpenSSL::SSL::SSLContext]
    #         a SSL context, configured with the certificate/key pair, which is used to connect to the APN service.
    #
    def ssl_context
      @ssl_context ||= OpenSSL::SSL::SSLContext.new.tap do |context|
        context.key = @key
        context.cert = @certificate
      end
    end

    # @return [Boolean]
    #         whether or not the certificate is a Universal Certificate.
    #
    # @see https://developer.apple.com/library/ios/documentation/IDEs/Conceptual/AppDistributionGuide/AddingCapabilities/AddingCapabilities.html#//apple_ref/doc/uid/TP40012582-CH26-SW11
    #
    def universal?
      !extension(UNIVERSAL_CERTIFICATE_EXTENSION).nil?
    end

    # @return [Boolean]
    #         whether or not the certificate supports the development (sandbox) environment (for development builds).
    #
    def development?
      !extension(DEVELOPMENT_ENV_EXTENSION).nil?
    end

    # @return [Boolean]
    #         whether or not the certificate supports the production environment (for Testflight & App Store builds).
    #
    def production?
      !extension(PRODUCTION_ENV_EXTENSION).nil?
    end

    # @return [Array<String>]
    #         a list of ‘topics’ that the certificate supports.
    #
    # @see https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/APNsProviderAPI.html
    #
    def topics
      if universal?
        components = extension(UNIVERSAL_CERTIFICATE_EXTENSION).value.split(/0?\.{2,}/)
        components.select.with_index { |_, index| index.odd? }
      else
        [app_bundle_id]
      end
    end

    # @return [String]
    #         the App ID / app’s Bundle ID that this certificate is for.
    #
    def app_bundle_id
      @certificate.subject.to_a.find { |key, *_| key == "UID" }[1]
    end

    private

    # http://images.apple.com/certificateauthority/pdf/Apple_WWDR_CPS_v1.13.pdf
    DEVELOPMENT_ENV_EXTENSION       = "1.2.840.113635.100.6.3.1".freeze
    PRODUCTION_ENV_EXTENSION        = "1.2.840.113635.100.6.3.2".freeze
    UNIVERSAL_CERTIFICATE_EXTENSION = "1.2.840.113635.100.6.3.6".freeze

    def extension(oid)
      @certificate.extensions.find { |ext| ext.oid == oid }
    end
  end
end

