$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "lowdown"

cert_file, environment, device_token = ARGV.first(3)
unless cert_file && environment && device_token
  puts "Usage: #{$PROGRAM_NAME} path/to/cert.pem [production|development] device-token"
  exit 1
end

production = environment == "production"

# $CELLULOID_DEBUG = true
# Celluloid.logger.level = Logger::DEBUG
# Celluloid.logger.level = Logger::INFO
Celluloid.logger.level = Logger::ERROR

# Connection time can take a while, just count the time it takes to connect.
start = nil

# The block form of Client#connect flushes and closes the connection at the end of the block.
Lowdown::Client.production(production, certificate: File.read(cert_file), pool_size: 2).connect do |group|
  start = Time.now
  600.times do
    notification = Lowdown::Notification.new(:token => device_token)
    notification.payload = { :alert => "Hello HTTP/2! ID=#{notification.id}" }
    group.send_notification(notification) do |response|
      if response.success?
        puts "Sent notification with ID: #{notification.id}"
      else
        puts "[!] (##{response.id}): #{response}"
      end
    end
  end
end

puts "Finished in #{Time.now - start} seconds"

