# frozen_string_literal: true

require "thread"

module Lutaml
  module Store
    class Cache
      DEFAULT_MAX_SIZE = 1000

      def initialize(max_size: DEFAULT_MAX_SIZE, ttl: nil)
        @max_size = max_size
        @ttl = ttl
        @data = {}
        @access_order = []
        @mutex = Mutex.new
      end

      # Get a value from cache
      # @param key [String] the key to retrieve
      # @return [String, nil] the cached value or nil if not found/expired
      def get(key)
        @mutex.synchronize do
          entry = @data[key]
          return nil unless entry
          return nil if expired?(entry)

          # Update access order for LRU
          @access_order.delete(key)
          @access_order << key
          entry[:value]
        end
      end

      # Store a value in cache
      # @param key [String] the key to store
      # @param value [String] the value to store
      def set(key, value)
        @mutex.synchronize do
          # Remove existing entry if present
          if @data.key?(key)
            @access_order.delete(key)
          end

          # Create new entry
          entry = {
            value: value,
            timestamp: Time.now
          }

          @data[key] = entry
          @access_order << key

          # Evict if over capacity
          evict_lru while @data.size > @max_size
        end
      end

      # Remove a value from cache
      # @param key [String] the key to remove
      # @return [Boolean] true if the key was present
      def delete(key)
        @mutex.synchronize do
          if @data.delete(key)
            @access_order.delete(key)
            true
          else
            false
          end
        end
      end

      # Check if a key exists in cache (and is not expired)
      # @param key [String] the key to check
      # @return [Boolean] true if key exists and is not expired
      def exists?(key)
        @mutex.synchronize do
          entry = @data[key]
          entry && !expired?(entry)
        end
      end

      # Clear all cached data
      def clear
        @mutex.synchronize do
          @data.clear
          @access_order.clear
        end
      end

      # Get current cache size
      # @return [Integer] number of items in cache
      def size
        @mutex.synchronize { @data.size }
      end

      # Get cache statistics
      # @return [Hash] cache statistics
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

      # Clean up expired entries
      # @return [Integer] number of entries removed
      def cleanup_expired
        @mutex.synchronize do
          expired_keys = @data.select { |_, entry| expired?(entry) }.keys
          expired_keys.each do |key|
            @data.delete(key)
            @access_order.delete(key)
          end
          expired_keys.size
        end
      end

      private

      # Check if an entry has expired
      # @param entry [Hash] the cache entry
      # @return [Boolean] true if expired
      def expired?(entry)
        return false unless @ttl

        Time.now - entry[:timestamp] > @ttl
      end

      # Evict the least recently used item
      def evict_lru
        return if @access_order.empty?

        lru_key = @access_order.shift
        @data.delete(lru_key)
      end
    end
  end
end
