# frozen_string_literal: true

require "json"
require_relative "store"

module Lutaml
  module Store
    class CacheStore < Store
      class CacheEntry
        attr_reader :value, :created_at, :ttl, :metadata

        def initialize(value, ttl: nil, metadata: {})
          @value = value
          @created_at = Time.now
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
            metadata: hash[:metadata] || {}
          ).tap do |entry|
            entry.instance_variable_set(:@created_at, Time.parse(hash[:created_at]))
          end
        end
      end

      def initialize(config = {})
        super
        @default_ttl = config[:default_ttl]
        @max_size = config[:max_size]
        @cleanup_interval = config[:cleanup_interval] || 300 # 5 minutes
        @last_cleanup = Time.now
        @access_times = {}
      end

      def get(key)
        cleanup_expired if should_cleanup?

        entry_data = adapter.load(key)
        return nil unless entry_data

        begin
          entry = deserialize_entry(entry_data)

          if entry.expired?
            delete(key)
            return nil
          end

          # Track access time for LRU
          @access_times[key] = Time.now
          entry.value
        rescue => e
          # If we can't deserialize the entry, treat it as a cache miss
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
        adapter.save(key, serialized_entry)

        @access_times[key] = Time.now
        value
      end

      def delete(key)
        # Get the value before deleting (without triggering cleanup)
        value = nil
        entry_data = adapter.load(key)
        if entry_data
          begin
            entry = deserialize_entry(entry_data)
            value = entry.value unless entry.expired?
          rescue
            # If we can't deserialize, treat as nil
          end
        end

        @access_times.delete(key)

        # Call the adapter's delete method
        deleted = adapter.delete(key)

        # Return the value if it was deleted, nil otherwise
        deleted ? value : nil
      end

      def clear
        @access_times.clear
        super
      end

      def exists?(key)
        # Check if key exists and is not expired
        return false unless super(key)

        entry_data = adapter.load(key)
        return false unless entry_data

        begin
          entry = deserialize_entry(entry_data)
          !entry.expired?
        rescue
          # If we can't deserialize, consider it as not existing
          false
        end
      end

      def keys
        cleanup_expired if should_cleanup?
        super.select { |key| exists?(key) }
      end

      def size
        cleanup_expired if should_cleanup?
        keys.size
      end

      # Cache-specific methods

      def ttl(key)
        entry_data = adapter.load(key)
        return nil unless entry_data

        begin
          entry = deserialize_entry(entry_data)
          return nil if entry.expired?

          return nil unless entry.ttl
          remaining = entry.ttl - (Time.now - entry.created_at)
          remaining > 0 ? remaining : nil
        rescue
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

        adapter.keys.each do |key|
          begin
            entry_data = adapter.load(key)
            next unless entry_data

            entry = deserialize_entry(entry_data)
            expired_keys << key if entry.expired?
          rescue
            # If we can't deserialize, consider it expired
            expired_keys << key
          end
        end

        expired_keys.each { |key| delete(key) }
        @last_cleanup = Time.now

        expired_keys.size
      end

      def cache_info
        total_keys = adapter.keys.size
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
        entry_data = adapter.load(key)
        return false unless entry_data

        begin
          entry = deserialize_entry(entry_data)
          return false if entry.expired?

          # Create new entry with updated TTL
          new_ttl = ttl || entry.ttl
          new_entry = CacheEntry.new(entry.value, ttl: new_ttl, metadata: entry.metadata)

          serialized_entry = serialize_entry(new_entry)
          adapter.save(key, serialized_entry)

          @access_times[key] = Time.now
          true
        rescue
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

      private

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

        # Evict least recently used entries
        keys_by_access = @access_times.sort_by { |_, time| time }.map(&:first)
        keys_to_evict = keys_by_access.first(size - @max_size + 1)

        keys_to_evict.each { |key| delete(key) }
      end
    end
  end
end
