require "fluent/plugin/filter"

module Fluent::Plugin
  class DockerJournaldConcatFilter < Filter
    Fluent::Plugin.register_filter("docker_journald_concat", self)

    helpers :timer, :event_emitter

    desc "The key to merge records on"
    config_param :key, :string, default: "message"
    desc "The key to test if record is multipart against"
    config_param :match_key, :string, default: "container_partial_message"
    desc "The key to determine which stream an event belongs to"
    config_param :stream_identity_key, :string, default: "container_id"
    desc "The interval between data flushes, 0 means disable timeout"
    config_param :flush_interval, :time, default: 60
    desc "The label name to handle timeout"
    config_param :timeout_label, :string, default: nil

    class TimeoutError < StandardError
    end

    def initialize
      super

      @buffer = Hash.new {|h, k| h[k] = [] }
      @timeout_map = Hash.new {|h, k| h[k] = Fluent::Engine.now }
    end

    def configure(conf)
      super

      @separator = ""
    end

    def start
      super

      @finished = false
      timer_execute(:filter_concat_timer, 1, &method(:on_timer))
    end

    def shutdown
      super

      @finished = true
      flush_shutdown_buffer
    end

    def filter_stream(tag, es)
      new_es = Fluent::MultiEventStream.new
      es.each do |time, record|
        if /\Afluent\.(?:trace|debug|info|warn|error|fatal)\z/ =~ tag
          new_es.add(time, record)
          next
        end
        begin
          flushed_es = process(tag, time, record)
          unless flushed_es.empty?
            flushed_es.each do |_time, new_record|
              new_es.add(time, record.merge(new_record))
            end
          end
        rescue => e
          router.emit_error_event(tag, time, record, e)
        end
      end
      new_es
    end

    private

    def on_timer
      return if @flush_interval <= 0
      return if @finished
      flush_timeout_buffer
    end

    def process(tag, time, record)
      stream_identity = "#{tag}:#{record[@stream_identity_key]}"
      @timeout_map[stream_identity] = Fluent::Engine.now
      new_es = Fluent::MultiEventStream.new
      if partial?(record[@match_key])
        # partial record
        @buffer[stream_identity] << [tag, time, record]
        return new_es
      elsif !@buffer[stream_identity].empty?
        # last partial record
        @buffer[stream_identity] << [tag, time, record]
        _, new_record = flush_buffer(stream_identity)
        new_es.add(time, new_record)
        return new_es
      end
      # regular record
      new_es.add(time, record)
      new_es
    end

    def partial?(text)
      /^true$/.match(text)
    end

    def sanitize_record(record)
      record.delete(@match_key)
    end

    def flush_buffer(stream_identity)
      lines = @buffer[stream_identity].map {|_tag, _time, record| record[@key] }
      _tag, time, first_record = @buffer[stream_identity].first
      new_record = {
        @key => lines.join(@separator)
      }
      @buffer[stream_identity].clear
      merged_record = first_record.merge(new_record)
      sanitize_record(merged_record)
      [time, merged_record]
    end

    def flush_timeout_buffer
      # now = Fluent::Engine.now
      now = Fluent::EventTime.now
      timeout_stream_identities = []
      @timeout_map.each do |stream_identity, previous_timestamp|
        next if @flush_interval > (now - previous_timestamp)
        next if @buffer[stream_identity].empty?
        time, record = flush_buffer(stream_identity)
        sanitize_record(record)
        timeout_stream_identities << stream_identity
        tag = stream_identity.split(":").first
        message = "Timeout flush: #{stream_identity}"
        handle_timeout_error(tag, time, record, message)
        log.info(message)
      end
      @timeout_map.reject! do |stream_identity, _|
        timeout_stream_identities.include?(stream_identity)
      end
    end

    def flush_shutdown_buffer
      @buffer.each do |stream_identity, elements|
        next if elements.empty?
        tag = stream_identity.split(":").first
        time, record = flush_buffer(stream_identity)
        router.emit(tag, time, record)
        log.info("Shutdown flush: #{stream_identity}")
      end
      @buffer.clear
      log.info("Filter docker_journald_concat shutdown finished")
    end

    def handle_timeout_error(tag, time, record, message)
      if @timeout_label
        event_router = event_emitter_router(@timeout_label)
        event_router.emit(tag, time, record)
      else
        router.emit_error_event(tag, time, record, TimeoutError.new(message))
      end
    end
  end
end
