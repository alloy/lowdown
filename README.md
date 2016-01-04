# Lowdown

Lowdown is a Ruby client for the HTTP/2 version of the Apple Push Notification Service.

Multiple notifications are multiplexed for efficiency.

NOTE: _It is not yet battle-tested and there is no documentation yet. This will all follow over the next few weeks._

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lowdown'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install lowdown

## Usage

You can use the `lowdown` bin that comes with this gem or in code at its simplest:

```ruby
notification = Lowdown::Notification.new(:token => "device-token", :payload => { :alert => "Hello World!" })

Lowdown::Client.production(true, File.read("path/to/certificate.pem")).connect do |client|
  client.send_notification(notification) do |response|
    if response.success?
      puts "Notification sent"
    else
      puts "Notification failed: #{response}"
    end
  end
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/alloy/lowdown.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

