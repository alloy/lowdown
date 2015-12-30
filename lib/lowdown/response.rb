module Lowdown
  class Response < Struct.new(:headers, :raw_body)
    # https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/APNsProviderAPI.html#//apple_ref/doc/uid/TP40008194-CH101-SW3
    STATUS_CODES = {
      200 => "Success",
      400 => "Bad request",
      403 => "There was an error with the certificate",
      405 => "The request used a bad :method value. Only POST requests are supported",
      410 => "The device token is no longer active for the topic",
      413 => "The notification payload was too large",
      429 => "The server received too many requests for the same device token",
      500 => "Internal server error",
      503 => "The server is shutting down and unavailable"
    }

    def id
      headers["apns-id"]
    end

    def unformatted_id(length = nil)
      id = self.id.tr('-', '')
      length ? id[32-length,length] : id.gsub(/\A0*/, '')
    end

    def status
      headers[":status"].to_i
    end

    def message
      STATUS_CODES[status]
    end

    def success?
      status == 200
    end

    def body
      JSON.parse(raw_body) if raw_body
    end

    def failure_reason
      body["reason"] unless success?
    end

    def invalid_token?
      status == 410
    end

    # Only available when using an invalid token.
    def validity_last_checked_at
      Time.at(body["timestamp"].to_i) if invalid_token?
    end

    def to_s
      "#{status} (#{message})#{": #{failure_reason}" unless success?}"
    end

    def inspect
      "#<Lowdown::Connection::Response #{to_s}>"
    end
  end
end
