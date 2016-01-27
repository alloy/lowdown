$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "lowdown"
require "logger"

cert_file, environment, device_token = ARGV.first(3)
unless cert_file && environment && device_token
  puts "Usage: #{$0} path/to/cert.pem [production|development] device-token"
  exit 1
end

#$CELLULOID_DEBUG = true
#Celluloid.logger.level = Logger::DEBUG
#Celluloid.logger.level = Logger::INFO
Celluloid.logger.level = Logger::ERROR

logger = Logger.new(STDOUT)

client = Lowdown::Client.production(environment == "production",
                                    certificate: File.read(cert_file),
                                    pool_size: 3,
                                    keep_alive: true) # This option is the key to long running connections
client.connect

loop do
  begin
    logger.info "Perform burst"
    # Perform a burst of notifications from multiple concurrent threads to demonstrate thread safety.
    #
    Array.new(3) do
      Thread.new do
        client.group do |group|
          10.times do
            notification = Lowdown::Notification.new(:token => device_token)
            notification.payload = { :alert => "Hello HTTP/2! ID=#{notification.id}" }
            group.send_notification(notification) do |response|
              if response.success?
                logger.debug "Sent notification with ID: #{notification.id}"
              else
                logger.error "[!] (##{response.id}): #{response}"
              end
            end
          end
        end
      end
    end.each(&:join)

    logger.info "Sleep for 5 seconds"
    sleep(5)

  rescue Interrupt
    logger.info "[!] Interrupt, exiting"
    break

  rescue Exception => e
    logger.error "[!] Exception occurred, re-trying in 1 second: #{e.inspect}\n\t#{e.backtrace.join("\n\t")}"
    sleep 1
    redo
  end
end

client.disconnect
puts "Finished!"

