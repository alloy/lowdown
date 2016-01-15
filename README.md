![](https://raw.githubusercontent.com/alloy/lowdown/master/doc/lowdown.png)

# Lowdown

[![Build Status](https://travis-ci.org/alloy/lowdown.svg?branch=master)](https://travis-ci.org/alloy/lowdown)

Lowdown is a Ruby client for the HTTP/2 version of the Apple Push Notification Service.

Multiple notifications are multiplexed for efficiency.

If you need to cotinuously send notifications, it’s a good idea to keep an open connection. Managing that, in for
instance a daemon, is beyond the scope of this library. We might release an extra daemon/server tool in the future that
provides this functionality, but for now you should simply use the Client provided in this library without the block
form (which automatically closes the connection) and build your own daemon/server setup, as required.

Also checkout [this library](https://github.com/alloy/time_zone_scheduler) for scheduling across time zones.

NOTE: _It is not yet battle-tested. This will all follow over the next few weeks._

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

You can use the `lowdown` bin that comes with this gem or for code usage see
[the documentation](http://www.rubydoc.info/gems/lowdown).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/alloy/lowdown.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

