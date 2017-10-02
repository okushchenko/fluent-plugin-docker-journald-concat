# fluent-plugin-docker-journald-concat

[![Gem Version](https://badge.fury.io/rb/fluent-plugin-docker-journald-concat.svg)](https://badge.fury.io/rb/fluent-plugin-docker-journald-concat)

Fluentd Filter plugin to concatenate partial log messages generated by Docker daemon with Journald logging driver

## Requirements

| fluent-plugin-docker-journald-concat | fluentd    | ruby   |
|--------------------------------------|------------|--------|
| >= 0.1.3                             | >= v0.14.0 | >= 2.1 |

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'fluent-plugin-docker-journald-concat'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install fluent-plugin-docker-journald-concat

## Configuration

**key**

The key to be concatenated for partial events.
Default value is `"message"`.

**match\_key**

The key which indicates a partial event.
Default value is `"container_partial_message"`.

**stream\_identity\_key**

The key to determine which stream an event belongs to.
Default value is `"container_id"`.

**flush\_interval**

The number of seconds after which the last received event will be flushed.
If specified 0, wait for next line forever.
Default value is `"60"`.

**timeout\_label**

The label assigned to timed out events.
Default value is `"nil"`.

## Usage

Insert this into your Fluentd config to get started.

```aconf
<filter docker.**>
  @type docker_journald_concat
</filter>
```

The full Fluentd config example with Systemd Journal input.

```aconf
<source>
  @type systemd
  tag docker
  path /var/log/journal
  read_from_head true
  filters [{ "_TRANSPORT": "journal", "_COMM": "dockerd" }]
  <storage>
    @type local
    persistent true
    path /tmp/journal.pos
  </storage>
  <entry>
    field_map {
      "_SOURCE_REALTIME_TIMESTAMP": "timestamp",
      "_HOSTNAME": "hostname",
      "PRIORITY": "priority",
      "MESSAGE": "message",
      "CONTAINER_NAME": "container_name",
      "CONTAINER_ID": "container_id",
      "CONTAINER_PARTIAL_MESSAGE": "container_partial_message"
    }
    field_map_strict true
  </entry>
</source>

<filter docker.**>
  @type record_modifier
  <record>
    # {"6" => "stdout", "3" => "stderr"}
    source ${record["priority"] == "6" ? "stdout" : "stderr"}
    timestamp ${record["timestamp"].to_i / 1000}
  </record>
  remove_keys priority
</filter>

<filter docker.**>
  @type docker_journald_concat
</filter>

<match docker.**>
  @type stdout
</match>
```

You can handle timeout events and remaining buffers on shutdown of this plugin.

```aconf
<label @ERROR>
  <match docker.log>
    @type file
    path /path/to/error.log
  </match>
</label>
```

Handle timed out log lines the same as normal logs.

```aconf
<filter **>
  @type docker_journald_concat
  timeout_label @NORMAL
</filter>

<match **>
  @type relabel
  @label @NORMAL
</match>

<label @NORMAL>
  <match **>
    @type stdout
  </match>
</label>
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
