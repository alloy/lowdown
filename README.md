![](https://raw.githubusercontent.com/alloy/lowdown/master/doc/lowdown.png)

# Lowdown

[![Build Status](https://travis-ci.org/alloy/lowdown.svg?branch=master)](https://travis-ci.org/alloy/lowdown)

⚠︎ NOTE: _This is not battle-tested yet, which will follow over the next few weeks. A v1 will be released at that time._

Lowdown is a Ruby client for the HTTP/2 version of the Apple Push Notification Service.

For efficiency, multiple notification requests are multiplexed and a single client can manage a pool of connections.

```
$ bundle exec ruby examples/simple.rb path/to/certificate.pem development <device-token>
Sent notification with ID: 13
Sent notification with ID: 1
Sent notification with ID: 10
Sent notification with ID: 7
Sent notification with ID: 25
...
Sent notification with ID: 10000
Sent notification with ID: 9984
Sent notification with ID: 9979
Sent notification with ID: 9992
Sent notification with ID: 9999
Finished in 14.98157 seconds
```

_This example was run with a pool of 10 connections._

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lowdown'
```

Or install it yourself, for instance for the command-line usage, as:

```
$ gem install lowdown
```

## Usage

You can use the `lowdown` bin that comes with this gem or for code usage see
[the documentation](http://www.rubydoc.info/gems/lowdown).

There are mainly two different modes in which you’ll typically use [this client][client]. Either you deliver a batch of
notifications every now and then, in which case you only want to open a connection to the remote service when needed, or
you need to be able to continuously deliver transactional notifications, in which case you’ll want to maintain
persistent connections. You can find examples of both these modes in the `examples` directory.

But first things first, this is how you create [a notification object][notification]:

```ruby
notification = Lowdown::Notification.new(:token => "device-token", :payload => { :alert => "Hello World!" })
```

There’s plenty more options for a notification, please refer to [the Notification documentation][notification].

### Short-lived connection

After obtaining a client, the simplest way to open a connection for a short period is by passing a block to `connect`.
This will open the connection, yield the block, and close the connection by the end of the block:

```ruby
client = Lowdown::Client.production(true, File.read("path/to/certificate.pem")
client.connect do |group|
  # ...
end
```

### Persistent connection

The trick to creating a persistent connection is to specify the `keep_alive: true` option when creating the client:

```ruby
client = Lowdown::Client.production(true, File.read("path/to/certificate.pem"), keep_alive: true)

# Send a batch of notifications
client.group do |group|
  # ...
end

# Send another batch of notifications
client.group do |group|
  # ...
end
```

One big difference you’ll notice with the short-lived connection example, is that you no longer use the `Client#connect`
method, nor do you close the connection (at least not until your process ends). Instead you use the `group` method to
group a set of deliveries.

### Grouping requests

Because Lowdown uses background threads to deliver notifications, the thread you’re delivering them _from_ would
normally chug along, which is often not what you’d want. To solve this, the `group` method provides you with [a group
object][group] which allows you to handle responses for the requests made in that group and halts the caller thread
until all responses have been handled.

All responses in a group will be handled in a single background thread, without halting the connection threads.

In typical Ruby fashion, a group provides a way to specify callbacks as blocks:

```ruby
group.send_notification(notification) do |response|
  # ...
end
```

But there’s another possiblity, which is to provide [a delegate object][delegate] which gets a message sent for each
response:

```ruby
class Delegate
  def handle_apns_response(response, context:)
    # ...
  end
end

delegate = Delegate.new

client.group do |group|
  group.send_notification(notification, delegate: delegate)
end
```

Keep in mind that, like with the block version, this message is sent on the group’s background thread.

### Threading

While we’re on the topic of threading anyways, here’s an important thing to keep in mind; each set of `group` callbacks
is performed on its own thread. It is thus _your_ responsibility to take this into account. E.g. if you are planning to
update a DB model with the status of a notification delivery, be sure to respect the treading rules of your DB client,
which usually means to not re-use models that were loaded on a different thread.

A simple approach to this is by passing the data you need to be able to update the DB as a `context`, which can be any
type of object or an array objects:

```ruby
group.send_notification(notification, context: model.id) do |response, model_id|
  reloaded_model = Model.find(model_id)
  if response.success?
    reloaded_model.touch(:sent_at)
  else
    reloaded_model.update_attribute(:last_response, response.status)
  end
end
```

### Connection pool

When you need to be able to deliver many notifications in a short amount of time, it can be beneficial to open multiple
connections to the remote service. By default Lowdown will initialize clients with a single connection, but you may
increase this with the `pool_size` option:

```ruby
Lowdown::Client.production(true, File.read("path/to/certificate.pem"), pool_size: 3)
```

## Related tool ☞

Also checkout [this library](https://github.com/alloy/time_zone_scheduler) for scheduling across time zones.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/alloy/lowdown.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

[client]: http://www.rubydoc.info/gems/lowdown/Lowdown/Client
[notification]: http://www.rubydoc.info/gems/lowdown/Lowdown/Notification
[group]: http://www.rubydoc.info/gems/lowdown/Lowdown/RequestGroup
[delegate]: http://www.rubydoc.info/gems/lowdown/Lowdown/Connection/DelegateProtocol
