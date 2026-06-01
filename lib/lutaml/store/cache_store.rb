# frozen_string_literal: true

require "json"

module Lutaml
  module Store
    # TTL-aware cache store with LRU eviction. Wraps a storage adapter directly.
    class CacheStore
      class CacheEntry
        attr_reader :value, :created_at, :ttl, :metadata

        def initialize(value, ttl: nil, metadata: {}, created_at: nil)
          @value = value
          @created_at = created_at || Time.now
          @ttl = ttl
          @metadata = metadata
        end

        def expired?
          return false unless @ttl

          Time.now - @created_at > @ttl
        end

        def expires_at
          return nil unless @ttl

          @created_at + @ttl
        end

        def to_h
          {
            value: @value,
            created_at: @created_at.iso8601,
            ttl: @ttl,
            expires_at: expires_at&.iso8601,
            metadata: @metadata
          }
        end

        def self.from_h(hash)
          new(
            hash[:value],
            ttl: hash[:ttl],
            metadata: hash[:metadata] || {},
            created_at: Time.parse(hash[:created_at])
          )
        end
      end

      attr_reader :adapter

      def initialize(config = {})
        @adapter = create_adapter(config)
        @default_ttl = config[:default_ttl]
        @max_size = config[:max_size]
        @cleanup_interval = config[:cleanup_interval] || 300
        @last_cleanup = Time.now
        @access_times = {}
      end

      def get(key)
        cleanup_expired if should_cleanup?

        entry_data = @adapter.get(key)
        return nil unless entry_data

        begin
          entry = deserialize_entry(entry_data)

          if entry.expired?
            delete(key)
            return nil
          end

          @access_times[key] = Time.now
          entry.value
        rescue StandardError
          delete(key)
          nil
        end
      end

      def set(key, value, ttl: :default, metadata: {})
        cleanup_expired if should_cleanup?
        evict_if_needed

        effective_ttl = ttl == :default ? @default_ttl : ttl
        entry = CacheEntry.new(value, ttl: effective_ttl, metadata: metadata)

        serialized_entry = serialize_entry(entry)
        @adapter.set(key, serialized_entry)

        @access_times[key] = Time.now
        value
      end

      def delete(key)
        value = nil
        entry_data = @adapter.get(key)
        if entry_data
          begin
            entry = deserialize_entry(entry_data)
            value = entry.value unless entry.expired?
          rescue StandardError
            # If we can't deserialize, treat as nil
          end
        end

        @access_times.delete(key)

        deleted = @adapter.delete(key)

        deleted ? value : nil
      end

      def clear
        @access_times.clear
        @adapter.clear
      end

      def exists?(key)
        return false unless @adapter.exists?(key)

        entry_data = @adapter.get(key)
        return false unless entry_data

        begin
          entry = deserialize_entry(entry_data)
          !entry.expired?
        rescue StandardError
          false
        end
      end

      def keys
        cleanup_expired if should_cleanup?
        @adapter.keys.select { |key| exists?(key) }
      end

      def size
        cleanup_expired if should_cleanup?
        keys.size
      end

      def ttl(key)
        entry_data = @adapter.get(key)
        return nil unless entry_data

        begin
          entry = deserialize_entry(entry_data)
          return nil if entry.expired?
          return nil unless entry.ttl

          remaining = entry.ttl - (Time.now - entry.created_at)
          remaining.positive? ? remaining : nil
        rescue StandardError
          nil
        end
      end

      def expire(key)
        delete(key)
      end

      def expire_all
        clear
      end

      def cleanup_expired
        expired_keys = []

        @adapter.each_key do |key|
          entry_data = @adapter.get(key)
          next unless entry_data

          entry = deserialize_entry(entry_data)
          expired_keys << key if entry.expired?
        rescue StandardError
          expired_keys << key
        end

        expired_keys.each { |key| delete(key) }
        @last_cleanup = Time.now

        expired_keys.size
      end

      def cache_info
        total_keys = @adapter.keys.size
        valid_keys = keys.size
        expired_keys = total_keys - valid_keys

        {
          total_entries: total_keys,
          valid_entries: valid_keys,
          expired_entries: expired_keys,
          max_size: @max_size,
          default_ttl: @default_ttl,
          last_cleanup: @last_cleanup
        }
      end

      def touch(key, ttl: nil)
        entry_data = @adapter.get(key)
        return false unless entry_data

        begin
          entry = deserialize_entry(entry_data)
          return false if entry.expired?

          new_ttl = ttl || entry.ttl
          new_entry = CacheEntry.new(entry.value, ttl: new_ttl, metadata: entry.metadata)

          serialized_entry = serialize_entry(new_entry)
          @adapter.set(key, serialized_entry)

          @access_times[key] = Time.now
          true
        rescue StandardError
          false
        end
      end

      def fetch(key, ttl: :default, metadata: {}, &block)
        value = get(key)
        return value unless value.nil?

        return nil unless block_given?

        value = block.call
        set(key, value, ttl: ttl, metadata: metadata)
        value
      end

      def close
        @adapter.close
      end

      private

      def create_adapter(config)
        adapter_type = config[:adapter]&.dig(:type) || config[:adapter_type] || :memory
        adapter_options = config[:adapter]&.dig(:options) || config[:adapter_options] || {}

        case adapter_type.to_sym
        when :memory
          Adapter::Memory.new(adapter_options)
        when :filesystem
          Adapter::FileSystem.new(adapter_options)
        when :sqlite
          Adapter::Sqlite.new(adapter_options)
        else
          raise ConfigurationError, "Unknown adapter type: #{adapter_type}"
        end
      end

      def serialize_entry(entry)
        JSON.generate(entry.to_h)
      end

      def deserialize_entry(data)
        hash = JSON.parse(data, symbolize_names: true)
        CacheEntry.from_h(hash)
      end

      def should_cleanup?
        Time.now - @last_cleanup > @cleanup_interval
      end

      def evict_if_needed
        return unless @max_size
        return if size < @max_size

        keys_by_access = @access_times.sort_by { |_, time| time }.map(&:first)
        keys_to_evict = keys_by_access.first(size - @max_size + 1)

        keys_to_evict.each { |key| delete(key) }
      end
    end
  end
end
