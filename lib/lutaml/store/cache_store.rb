# frozen_string_literal: true

require "json"
require "monitor"
require "time"

module Lutaml
  module Store
    # TTL-aware cache store with LRU eviction. Wraps a storage adapter directly.
    #
    # All public operations run under one re-entrant lock, so the LRU and
    # cleanup bookkeeping is safe across threads. Across processes only the
    # adapter's own guarantees apply.
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
        @lock = ::Monitor.new
      end

      def get(key)
        @lock.synchronize do
          cleanup_if_due

          entry_data = @adapter.get(key)
          next nil unless entry_data

          begin
            entry = deserialize_entry(entry_data)

            if entry.expired?
              delete(key)
              next nil
            end

            @access_times[key] = Time.now
            entry.value
          rescue StandardError
            delete(key)
            nil
          end
        end
      end

      def set(key, value, ttl: :default, metadata: {})
        @lock.synchronize do
          cleanup_if_due
          evict_if_needed

          effective_ttl = ttl == :default ? @default_ttl : ttl
          entry = CacheEntry.new(value, ttl: effective_ttl, metadata: metadata)

          serialized_entry = serialize_entry(entry)
          @adapter.set(key, serialized_entry)

          @access_times[key] = Time.now
          value
        end
      end

      def delete(key)
        @lock.synchronize do
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
      end

      def clear
        @lock.synchronize do
          @access_times.clear
          @adapter.clear
        end
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
        @lock.synchronize do
          cleanup_if_due
          @adapter.keys.select { |key| exists?(key) }
        end
      end

      def size
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
        @lock.synchronize { cleanup_expired_entries }
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
        @lock.synchronize do
          entry_data = @adapter.get(key)
          next false unless entry_data

          begin
            entry = deserialize_entry(entry_data)
            next false if entry.expired?

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
      end

      def fetch(key, default = nil, ttl: :default, metadata: {})
        value = get(key)
        return value unless value.nil?

        if block_given?
          value = yield
          set(key, value, ttl: ttl, metadata: metadata)
          value
        elsif !default.nil?
          set(key, default, ttl: ttl, metadata: metadata)
          default
        end
      end

      def close
        @adapter.close
      end

      private

      def create_adapter(config)
        adapter_type = config[:adapter]&.dig(:type) || config[:adapter_type] || :memory
        adapter_options = config[:adapter]&.dig(:options) || config[:adapter_options] || {}

        Adapter.resolve(adapter_type, adapter_options)
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

      # Caller holds @lock.
      def cleanup_if_due
        cleanup_expired_entries if should_cleanup?
      end

      # Caller holds @lock. @last_cleanup is set first, so a nested call
      # (through #delete) does not start a second scan.
      def cleanup_expired_entries
        @last_cleanup = Time.now
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

        expired_keys.size
      end

      # Caller holds @lock. Keys this process never touched count as the
      # least recently used.
      def evict_if_needed
        return unless @max_size

        stored_keys = @adapter.keys
        overflow = stored_keys.size - @max_size + 1
        return unless overflow.positive?

        untouched = stored_keys.reject { |key| @access_times.key?(key) }
        by_access = @access_times.sort_by { |_, time| time }.map(&:first)

        (untouched + by_access).first(overflow).each { |key| delete(key) }
      end
    end
  end
end
