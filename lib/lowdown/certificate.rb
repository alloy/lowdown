require "openssl"

module Lowdown
  class Certificate
    # http://images.apple.com/certificateauthority/pdf/Apple_WWDR_CPS_v1.13.pdf
    DEVELOPMENT_ENV_EXTENSION       = "1.2.840.113635.100.6.3.1".freeze
    PRODUCTION_ENV_EXTENSION        = "1.2.840.113635.100.6.3.2".freeze
    UNIVERSAL_CERTIFICATE_EXTENSION = "1.2.840.113635.100.6.3.6".freeze

    def self.from_pem_data(data)
      key = OpenSSL::PKey::RSA.new(data, nil)
      certificate = OpenSSL::X509::Certificate.new(data)
      new(key, certificate)
    end

    attr_reader :key, :certificate

    def initialize(key, certificate)
      @key, @certificate = key, certificate
    end

    def to_pem
      "#{@key.to_pem}\n#{@certificate.to_pem}"
    end

    def ssl_context
      @ssl_context ||= OpenSSL::SSL::SSLContext.new.tap do |context|
        context.key = @key
        context.cert = @certificate
      end
    end

    def universal?
      !extension(UNIVERSAL_CERTIFICATE_EXTENSION).nil?
    end

    def development?
      !extension(DEVELOPMENT_ENV_EXTENSION).nil?
    end

    def production?
      !extension(PRODUCTION_ENV_EXTENSION).nil?
    end

    def topics
      if universal?
        components = extension(UNIVERSAL_CERTIFICATE_EXTENSION).value.split(/0?\.{2,}/)
        components.select.with_index { |_, index| index.odd? }
      else
        [app_bundle_id]
      end
    end

    private

    def extension(oid)
      @certificate.extensions.find { |ext| ext.oid == oid }
    end

    def app_bundle_id
      @certificate.subject.to_a.find { |key, *_| key == 'UID' }[1]
    end
  end
end
