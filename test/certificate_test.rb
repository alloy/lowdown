require "test_helper"
require "lowdown/mock"

module Lowdown
  describe Certificate do
    parallelize_me!

    before do
      @cert, @key = Mock.ssl_certificate_and_key("com.example.MockAPNS")
      @certificate = Certificate.new(@cert, @key)
    end

    it "initializes with cert and key PEM data" do
      certificate = Certificate.from_pem_data(@certificate.to_pem)
      certificate.key.to_pem.must_equal @key.to_pem
      certificate.certificate.to_pem.must_equal @cert.to_pem
    end

    it "returns a configured OpenSSL context" do
      @certificate.ssl_context.key.must_equal @key
      @certificate.ssl_context.cert.must_equal @cert
    end

    it "returns whether or not the certificate supports the development environment" do
      @certificate.development?.must_equal false

      @cert.extensions = [OpenSSL::X509::Extension.new(Certificate::DEVELOPMENT_ENV_EXTENSION, "..")]
      @certificate.development?.must_equal true
    end

    it "returns whether or not the certificate supports the production environment" do
      @certificate.production?.must_equal false

      @cert.extensions = [OpenSSL::X509::Extension.new(Certificate::PRODUCTION_ENV_EXTENSION, "..")]
      @certificate.production?.must_equal true
    end

    describe "with a non-universal certificate" do
      parallelize_me!

      before do
        @cert.extensions = []
      end

      it "returns that it’s not a universal certificate" do
        @certificate.universal?.must_equal false
      end

      it "returns only the app bundle ID as available topic" do
        @certificate.topics.must_equal ["com.example.MockAPNS"]
      end
    end

    describe "with a universal certificate" do
      parallelize_me!

      before do
        value = %w{
          0d
          com.example.MockAPNS0...app
          com.example.MockAPNS.voip0...voip
          com.example.MockAPNS.complication0...complication
        }.join("..")
        @cert.extensions = [OpenSSL::X509::Extension.new(Certificate::UNIVERSAL_CERTIFICATE_EXTENSION, value)]
      end

      it "returns that it’s a universal certificate" do
        @certificate.universal?.must_equal true
      end

      it "returns all the available topics" do
        @certificate.topics.must_equal %w{ com.example.MockAPNS com.example.MockAPNS.voip com.example.MockAPNS.complication }
      end
    end
  end
end
