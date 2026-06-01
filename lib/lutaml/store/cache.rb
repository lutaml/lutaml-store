# frozen_string_literal: true

module Lutaml
  module Store
    class Cache
      Entry = Struct.new(:value, :timestamp, keyword_init: true)

      DEFAULT_MAX_SIZE = 1000

      def initialize(max_size: DEFAULT_MAX_SIZE, ttl: nil)
        @max_size = max_size
        @ttl = ttl
        @data = {}
        @access_order = []
        @mutex = Mutex.new
      end

      def get(key)
        @mutex.synchronize do
          entry = @data[key]
          return nil unless entry
          return nil if expired?(entry)

          @access_order.delete(key)
          @access_order << key
          entry.value
        end
      end

      def set(key, value)
        @mutex.synchronize do
          @access_order.delete(key) if @data.key?(key)

          @data[key] = Entry.new(value: value, timestamp: Time.now)
          @access_order << key

          evict_lru while @data.size > @max_size
        end
      end

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

      def exists?(key)
        @mutex.synchronize do
          entry = @data[key]
          entry && !expired?(entry)
        end
      end

      def clear
        @mutex.synchronize do
          @data.clear
          @access_order.clear
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
            @access_order.delete(key)
          end
          expired_keys.size
        end
      end

      private

      def expired?(entry)
        return false unless @ttl

        Time.now - entry.timestamp > @ttl
      end

      def evict_lru
        return if @access_order.empty?

        lru_key = @access_order.shift
        @data.delete(lru_key)
      end
    end
  end
end
