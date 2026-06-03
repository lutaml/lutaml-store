# frozen_string_literal: true

module Lutaml
  module Store
    class BasicStore
      attr_reader :adapter, :cache, :monitor, :events, :config

      def initialize(config_or_adapter = {})
        if config_or_adapter.is_a?(Adapter::Base)
          @adapter = config_or_adapter
          @config = Config.new
        elsif config_or_adapter.is_a?(Config)
          @config = config_or_adapter
          @adapter = create_adapter
        else
          @config = Config.new(**config_or_adapter.transform_keys(&:to_sym))
          @adapter = create_adapter
        end

        @config.validate!

        @cache = @config.cache_enabled? ? create_cache : nil
        @monitor = @config.monitoring_enabled? ? Monitor.new : nil
        @events = Events.new(async: @config.async_events?)
      end

      def self.from_file(file_path)
        new(Config.from_file(file_path))
      end

      def self.from_yaml(yaml_string)
        new(Config.from_yaml(yaml_string))
      end

      def get(key)
        with_monitoring(:get) do
          if @cache
            cached_value = @cache.get(key)
            if cached_value
              emit_event(:get, key: key, value: cached_value, source: :cache)
              next cached_value
            end
          end

          value = @adapter.get(key)
          @cache&.set(key, value) if value
          emit_event(:get, key: key, value: value, source: :adapter)
          value
        end
      end

      def set(key, value)
        with_monitoring(:set) do
          @adapter.set(key, value)
          @cache&.set(key, value)
          emit_event(:set, key: key, value: value)
        end
      end

      def delete(key)
        with_monitoring(:delete) do
          result = @adapter.delete(key)
          @cache&.delete(key) if result
          emit_event(:delete, key: key, deleted: result)
          result
        end
      end

      def exists?(key)
        with_monitoring(:exists) do
          next true if @cache&.exists?(key)

          @adapter.exists?(key)
        end
      end

      def all
        with_monitoring(:all) do
          @adapter.all
        end
      end

      def clear
        with_monitoring(:clear) do
          @adapter.clear
          @cache&.clear
          emit_event(:clear)
        end
      end

      def size
        with_monitoring(:size) do
          @adapter.size
        end
      end

      def keys
        @adapter.keys
      end

      def each_key(&block)
        @adapter.keys.each(&block)
      end

      def bulk_get(keys)
        @adapter.bulk_get(keys)
      end

      def bulk_set(key_value_pairs)
        @adapter.bulk_set(key_value_pairs)
        key_value_pairs.each { |key, value| @cache&.set(key, value) }
      end

      def bulk_delete(keys)
        result = @adapter.bulk_delete(keys)
        keys.each { |key| @cache&.delete(key) }
        result
      end

      def on(event, callable = nil, &block)
        @events.on(event, callable, &block)
      end

      def off(event, listener)
        @events.off(event, listener)
      end

      def emit_event(event, data = {})
        @events.emit(event, data)
      end

      def stats
        base_stats = {
          adapter: @adapter.class.name,
          size: size,
          cache_enabled: !@cache.nil?,
          monitoring_enabled: !@monitor.nil?
        }

        base_stats[:adapter_stats] = @adapter.stats
        base_stats[:cache_stats] = @cache.stats if @cache
        base_stats[:monitor_stats] = @monitor.stats if @monitor

        base_stats
      end

      def cache_stats
        @cache&.stats
      end

      def close
        @events.stop if @config.async_events?
        @adapter.close
      end

      private

      def with_monitoring(operation)
        start_time = Time.now
        result = yield
        record_operation(operation, Time.now - start_time, true)
        result
      rescue StandardError => e
        record_operation(operation, Time.now - start_time, false)
        @monitor&.record_error(operation, e)
        raise
      end

      def create_adapter
        case @config.adapter_type
        when :memory
          Adapter::Memory.new(@config.adapter_options)
        when :filesystem
          Adapter::FileSystem.new(@config.adapter_options)
        when :sqlite
          Adapter::Sqlite.new(@config.adapter_options)
        else
          raise ConfigurationError, "Unknown adapter type: #{@config.adapter_type}"
        end
      end

      def create_cache
        Cache.new(
          max_size: @config.cache_max_size,
          ttl: @config.cache_ttl
        )
      end

      def record_operation(operation, duration, success)
        @monitor&.record_operation(operation, duration: duration, success: success)
      end
    end
  end
end
