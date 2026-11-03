# frozen_string_literal: true

module Lutaml
  module Store
    class Cache
      Entry = Struct.new(:value, :timestamp, keyword_init: true)

      DEFAULT_MAX_SIZE = 1000

      # LRU over Hash insertion order: re-inserting a key moves it to the
      # newest position, so the first entry is always the least recently
      # used. Ruby Hashes are ordered, which keeps every operation O(1);
      # the previous access-order Array re-scanned on every hit (O(n),
      # ~40us per hit at 1000 entries, all under the lock).
      def initialize(max_size: DEFAULT_MAX_SIZE, ttl: nil)
        @max_size = max_size
        @ttl = ttl
        @data = {}
        @mutex = Mutex.new
      end

      def get(key)
        @mutex.synchronize do
          entry = @data[key]
          return nil unless entry
          return nil if expired?(entry)

          refresh_recency(key, entry)
          entry.value
        end
      end

      def set(key, value)
        @mutex.synchronize do
          @data.delete(key)
          @data[key] = Entry.new(value: value, timestamp: Time.now)

          evict_lru while @data.size > @max_size
        end
      end

      def delete(key)
        @mutex.synchronize do
          entry = @data.delete(key)
          entry ? true : false
        end
      end

      def exists?(key)
        @mutex.synchronize do
          entry = @data[key]
          return false unless entry

          !expired?(entry)
        end
      end

      def clear
        @mutex.synchronize do
          @data.clear
        end
      end

      def size
        @mutex.synchronize { @data.size }
      end

      def stats
        @mutex.synchronize do
          {
            size: @data.size,
            max_size: @max_size,
            ttl: @ttl,
            keys: @data.keys
          }
        end
      end

      def cleanup_expired
        @mutex.synchronize do
          expired_keys = @data.select { |_, entry| expired?(entry) }.keys
          expired_keys.each do |key|
            @data.delete(key)
          end
          expired_keys.size
        end
      end

      private

      def refresh_recency(key, entry)
        @data.delete(key)
        @data[key] = entry
      end

      def expired?(entry)
        return false unless @ttl

        Time.now - entry.timestamp > @ttl
      end

      def evict_lru
        return if @data.empty?

        oldest_key = @data.each_key.first
        @data.delete(oldest_key)
      end
    end
  end
end
