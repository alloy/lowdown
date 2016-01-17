require "lowdown/client"
require "lowdown/version"

# Lowdown is a Ruby client for the HTTP/2 version of the Apple Push Notification Service.
#
# Multiple notifications are multiplexed and responses are yielded onto a different thread for efficiency.
#
# Note that it is thus _your_ responsibility to take the threading issue into account. E.g. if you are planning to
# update a DB model with the status of a notification delivery, be sure to respect the treading rules of your DB client.
#
# The main classes you will interact with are {Lowdown::Client} and {Lowdown::Notification}. For testing purposes there
# are some helpers available in {Lowdown::Mock}.
#
# @example At its simplest, you can send a notification like so:
#
#     notification = Lowdown::Notification.new(:token => "device-token", :payload => { :alert => "Hello World!" })
#
#     Lowdown::Client.production(true, File.read("path/to/certificate.pem")).connect do |client|
#       client.send_notification(notification) do |response|
#         if response.success?
#           puts "Notification sent"
#         else
#           puts "Notification failed: #{response}"
#         end
#       end
#     end
#
module Lowdown
end
