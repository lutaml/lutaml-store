# frozen_string_literal: true

require_relative "adapter/base"
require_relative "adapter/memory"
require_relative "adapter/filesystem"
require_relative "adapter/sqlite"

module Lutaml
  module Store
    class Store
      attr_reader :adapter, :cache, :monitor, :events, :config

      # Initialize a new store
      # @param config_or_adapter [Config, Hash, Adapter::Base] configuration, config hash, or adapter instance
      def initialize(config_or_adapter = {})
        if config_or_adapter.is_a?(Adapter::Base)
          @adapter = config_or_adapter
          @config = Config.new
        elsif config_or_adapter.is_a?(Config)
          @config = config_or_adapter
          @adapter = create_adapter
        else
          @config = Config.new(config_or_adapter)
          @adapter = create_adapter
        end

        @config.validate!

        @cache = @config.cache_enabled? ? create_cache : nil
        @monitor = @config.monitoring_enabled? ? Monitor.new : nil
        @events = Events.new(async: @config.async_events?)
      end

      # Create a store from configuration file
      # @param file_path [String] path to YAML configuration file
      # @return [Store] new store instance
      def self.from_file(file_path)
        config = Config.from_file(file_path)
        new(config)
      end

      # Create a store from YAML string
      # @param yaml_string [String] YAML configuration as string
      # @return [Store] new store instance
      def self.from_yaml(yaml_string)
        config = Config.from_yaml(yaml_string)
        new(config)
      end

      # Load configuration from file (for backward compatibility)
      def self.load_config(config_file)
        Config.from_file(config_file)
      end

      # Retrieve a value by key
      # @param key [String] the key to retrieve
      # @return [String, nil] the value or nil if not found
      def get(key)
        start_time = Time.now

        begin
          # Try cache first
          if @cache
            cached_value = @cache.get(key)
            if cached_value
              record_operation(:get, Time.now - start_time, true)
              emit_event(:get, key: key, value: cached_value, source: :cache)
              return cached_value
            end
          end

          # Get from adapter
          value = @adapter.get(key)

          # Cache the value if found
          @cache&.set(key, value) if value

          record_operation(:get, Time.now - start_time, true)
          emit_event(:get, key: key, value: value, source: :adapter)
          value
        rescue => e
          record_operation(:get, Time.now - start_time, false)
          @monitor&.record_error(:get, e)
          raise
        end
      end

      # Store a value with a key
      # @param key [String] the key to store
      # @param value [String] the value to store
      # @return [void]
      def set(key, value)
        start_time = Time.now

        begin
          @adapter.set(key, value)
          @cache&.set(key, value)

          record_operation(:set, Time.now - start_time, true)
          emit_event(:set, key: key, value: value)
        rescue => e
          record_operation(:set, Time.now - start_time, false)
          @monitor&.record_error(:set, e)
          raise
        end
      end

      # Delete a value by key
      # @param key [String] the key to delete
      # @return [Boolean] true if the key existed and was deleted
      def delete(key)
        start_time = Time.now

        begin
          result = @adapter.delete(key)
          @cache&.delete(key) if result

          record_operation(:delete, Time.now - start_time, true)
          emit_event(:delete, key: key, deleted: result)
          result
        rescue => e
          record_operation(:delete, Time.now - start_time, false)
          @monitor&.record_error(:delete, e)
          raise
        end
      end

      # Check if a key exists
      # @param key [String] the key to check
      # @return [Boolean] true if the key exists
      def exists?(key)
        start_time = Time.now

        begin
          # Check cache first
          if @cache && @cache.exists?(key)
            record_operation(:exists, Time.now - start_time, true)
            return true
          end

          result = @adapter.exists?(key)
          record_operation(:exists, Time.now - start_time, true)
          result
        rescue => e
          record_operation(:exists, Time.now - start_time, false)
          @monitor&.record_error(:exists, e)
          raise
        end
      end

      # Get all key-value pairs
      # @return [Hash] all stored key-value pairs
      def all
        start_time = Time.now

        begin
          result = @adapter.all
          record_operation(:all, Time.now - start_time, true)
          result
        rescue => e
          record_operation(:all, Time.now - start_time, false)
          @monitor&.record_error(:all, e)
          raise
        end
      end

      # Clear all stored data
      # @return [void]
      def clear
        start_time = Time.now

        begin
          @adapter.clear
          @cache&.clear

          record_operation(:clear, Time.now - start_time, true)
          emit_event(:clear)
        rescue => e
          record_operation(:clear, Time.now - start_time, false)
          @monitor&.record_error(:clear, e)
          raise
        end
      end

      # Get the number of stored items
      # @return [Integer] the number of items
      def size
        start_time = Time.now

        begin
          result = @adapter.size
          record_operation(:size, Time.now - start_time, true)
          result
        rescue => e
          record_operation(:size, Time.now - start_time, false)
          @monitor&.record_error(:size, e)
          raise
        end
      end

      # Get all keys
      # @return [Array<String>] all stored keys
      def keys
        @adapter.keys
      end

      # Bulk operations
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

      # Register an event listener
      # @param event [Symbol] the event to listen for
      # @param callable [Proc, #call] the listener to call when event occurs
      def on(event, callable = nil, &block)
        @events.on(event, callable, &block)
      end

      # Remove an event listener
      # @param event [Symbol] the event to remove listener from
      # @param listener [Proc, #call] the listener to remove
      def off(event, listener)
        @events.off(event, listener)
      end

      # Get monitoring statistics
      # @return [Hash, nil] monitoring statistics or nil if monitoring disabled
      def stats
        base_stats = {
          adapter: @adapter.class.name,
          size: size,
          cache_enabled: !@cache.nil?,
          monitoring_enabled: !@monitor.nil?
        }

        base_stats[:adapter_stats] = @adapter.stats if @adapter.respond_to?(:stats)
        base_stats[:cache_stats] = @cache.stats if @cache&.respond_to?(:stats)
        base_stats[:monitor_stats] = @monitor.stats if @monitor&.respond_to?(:stats)

        base_stats
      end

      # Get cache statistics
      # @return [Hash, nil] cache statistics or nil if caching disabled
      def cache_stats
        @cache&.stats
      end

      # Close the store and clean up resources
      def close
        @events.stop if @config.async_events?
        @adapter.close if @adapter.respond_to?(:close)
      end

      private

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

      def emit_event(event, data = {})
        @events.emit(event, data)
      end
    end
  end
end
