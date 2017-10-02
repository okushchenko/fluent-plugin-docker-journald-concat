require "helper"
require "fluent/test/driver/filter"
class FilterConcatTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
    @time = Fluent::EventTime.now
  end

  def create_driver(conf)
    Fluent::Test::Driver::Filter.new(Fluent::Plugin::DockerJournalConcatFilter).configure(conf, syntax: :v1)
  end

  def filter(conf, messages, wait: nil)
    d = create_driver(conf)
    yield d if block_given?
    d.run(default_tag: "test") do
      sleep 0.1 # run event loop
      messages.each do |message|
        d.feed(@time, message)
      end
      sleep wait if wait
    end
    d.filtered_records
  end

  def filter_with_time(conf, messages, wait: nil)
    d = create_driver(conf)
    yield d if block_given?
    d.run(default_tag: "test") do
      sleep 0.1 # run event loop
      messages.each do |time, message|
        d.feed(time, message)
      end
      sleep wait if wait
    end
    d.filtered
  end

  class Simple < self
    def test_filter_empty
      messages = [
        { "message" => "message 1" },
        { "message" => "message 2" },
        { "message" => "message 3" },
      ]
      expected = [
        { "message" => "message 1" },
        { "message" => "message 2" },
        { "message" => "message 3" },
      ]
      filtered = filter("", messages)
      assert_equal(expected, filtered)
    end

    def test_filter
      messages = [
        { "container_partial_message" => "true", "message" => "message 1" },
        { "container_partial_message" => "true", "message" => "message 2" },
        { "message" => "message 3" },
      ]
      expected = [
        { "message" => "message 1message 2message 3" },
      ]
      filtered = filter("", messages)
      assert_equal(expected, filtered)
    end

    def test_stream_identity
      messages = [
        { "container_partial_message" => "true", "container_id" => "1", "message" => "message 1" },
        { "container_partial_message" => "true", "container_id" => "2", "message" => "message 2" },
        { "container_partial_message" => "true", "container_id" => "1", "message" => "message 3" },
        { "container_partial_message" => "true", "container_id" => "2", "message" => "message 4" },
        { "container_id" => "1", "message" => "message 5" },
        { "container_id" => "2", "message" => "message 6" },
      ]
      expected = [
        { "container_id" => "1", "message" => "message 1message 3message 5" },
        { "container_id" => "2", "message" => "message 2message 4message 6" },
      ]
      filtered = filter("stream_identity_key container_id", messages)
      assert_equal(expected, filtered)
    end

    def test_timeout
      messages = [
        { "container_partial_message" => "true", "container_id" => "1", "message" => "message 1" },
        { "container_partial_message" => "true", "container_id" => "1", "message" => "message 2" },
      ]
      filtered = filter("flush_interval 2s", messages, wait: 3) do |d|
        errored = { "container_id" => "1", "message" => "message 1message 2" }
        mock(d.instance.router).emit_error_event("test", anything, errored, anything)
      end
      assert_equal([], filtered)
    end

    def test_timeout_with_timeout_label
      messages = [
        { "container_partial_message" => "true", "container_id" => "1", "message" => "message 1" },
        { "container_partial_message" => "true", "container_id" => "1", "message" => "message 2" },
      ]
      filtered = filter("flush_interval 2s\ntimeout_label @TIMEOUT", messages, wait: 3) do
        errored = { "container_id" => "1", "message" => "message 1message 2" }
        event_router = mock(Object.new).emit("test", anything, errored)
        mock(Fluent::Test::Driver::TestEventRouter).new(anything) { event_router }
      end
      assert_equal([], filtered)
    end

    def test_shutdown
      messages = [
        { "container_partial_message" => "true", "container_id" => "1", "message" => "message 1" },
        { "container_partial_message" => "true", "container_id" => "1", "message" => "message 2" },
        { "container_partial_message" => "true", "container_id" => "1", "message" => "message 3" },
      ]
      filtered = filter("", messages) do |d|
        errored = { "container_id" => "1", "message" => "message 1message 2message 3" }
        mock(d.instance.router).emit("test", anything, errored)
        mock(d.instance.router).emit_error_event("test", anything, errored, anything).times(0)
      end
      expected = []
      assert_equal(expected, filtered)
    end
  end

  class Multiline < self
    def test_filter
      config = <<-CONFIG
        key message
        multiline_start_regexp /^start/
      CONFIG
      messages = [
        { "message" => "message 1" },
        { "message" => "message 2" },
        { "container_partial_message" => "true", "message" => "message 3" },
        { "container_partial_message" => "true", "message" => "message 4" },
        { "message" => "message 5" },
        { "message" => "message 6" },
        { "message" => "message 7" },
      ]
      expected = [
        { "message" => "message 1" },
        { "message" => "message 2" },
        { "message" => "message 3message 4message 5" },
        { "message" => "message 6" },
        { "message" => "message 7" },
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end
  end
end
