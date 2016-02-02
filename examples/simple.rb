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
Celluloid.logger.level = Logger::INFO
# Celluloid.logger.level = Logger::ERROR

client = Lowdown::Client.production(production, certificate: File.read(cert_file), pool_size: 2)

# The block form of Client#connect flushes and closes the connection at the end of the block.
loop do
  begin
    client.connect do |group|
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
  rescue Interrupt
    puts "[!] Interrupt, exiting"
    break

  rescue Exception => e
    puts "[!] Error occurred: #{e.message}"
  end

  GC.start
  puts "Sleep for 5 seconds"
  sleep(5)
end

