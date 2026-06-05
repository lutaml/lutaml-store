# frozen_string_literal: true

module Lutaml
  module Store
    module Adapter
      class Memory < Base
        def initialize(config = {})
          super
          @data = {}
          @mutex = Mutex.new
          @ttl_enabled = @config.fetch(:ttl_enabled, false)
          @ttl_data = {} if @ttl_enabled
          @default_ttl = @config[:default_ttl] || 3600
        end

        def get(key)
          @mutex.synchronize do
            return nil unless @data.key?(key)

            if @ttl_enabled && expired?(key)
              @data.delete(key)
              @ttl_data.delete(key)
              return nil
            end

            @data[key]
          end
        end

        def set(key, value, metadata = {})
          @mutex.synchronize do
            @data[key] = value

            if @ttl_enabled
              ttl_value = metadata[:ttl] || @default_ttl
              @ttl_data[key] = Time.now + ttl_value if ttl_value
            end

            value
          end
        end

        def delete(key)
          @mutex.synchronize do
            existed = @data.key?(key)
            @data.delete(key)
            @ttl_data.delete(key) if @ttl_enabled
            existed
          end
        end

        def exists?(key)
          @mutex.synchronize do
            return false unless @data.key?(key)

            if @ttl_enabled && expired?(key)
              @data.delete(key)
              @ttl_data.delete(key)
              return false
            end

            true
          end
        end

        def all
          @mutex.synchronize do
            cleanup_expired if @ttl_enabled
            @data.dup
          end
        end

        def clear
          @mutex.synchronize do
            count = @data.size
            @data.clear
            @ttl_data.clear if @ttl_enabled
            count
          end
        end

        def size
          @mutex.synchronize do
            cleanup_expired if @ttl_enabled
            @data.size
          end
        end

        def keys
          @mutex.synchronize do
            cleanup_expired if @ttl_enabled
            @data.keys
          end
        end

        def each_key(&block)
          current_keys = @mutex.synchronize do
            cleanup_expired if @ttl_enabled
            @data.keys
          end
          current_keys.each(&block)
        end

        def close
          @mutex.synchronize do
            @data.clear
            @ttl_data.clear if @ttl_enabled
          end
        end

        def stats
          @mutex.synchronize do
            cleanup_expired if @ttl_enabled
            super.merge(
              size: @data.size,
              ttl_enabled: @ttl_enabled,
              expired_keys: @ttl_enabled ? count_expired_keys : 0
            )
          end
        end

        def cleanup_expired
          return unless @ttl_enabled

          @mutex.synchronize do
            expired_keys = []
            @ttl_data.each do |key, expiry_time|
              expired_keys << key if Time.now > expiry_time
            end

            expired_keys.each do |key|
              @data.delete(key)
              @ttl_data.delete(key)
            end

            expired_keys.size
          end
        end

        def set_ttl(key, ttl)
          return false unless @ttl_enabled

          @mutex.synchronize do
            return false unless @data.key?(key)

            if ttl
              @ttl_data[key] = Time.now + ttl
            else
              @ttl_data.delete(key)
            end

            true
          end
        end

        def get_ttl(key)
          return nil unless @ttl_enabled

          @mutex.synchronize do
            return nil unless @ttl_data.key?(key)

            expiry_time = @ttl_data[key]
            remaining = expiry_time - Time.now
            remaining.positive? ? remaining : nil
          end
        end

        def bulk_set(key_value_pairs, ttl: nil)
          @mutex.synchronize do
            key_value_pairs.each do |key, value|
              @data[key] = value

              if @ttl_enabled
                ttl_value = ttl || @default_ttl
                @ttl_data[key] = Time.now + ttl_value if ttl_value
              end
            end
          end
        end

        def bulk_get(keys)
          @mutex.synchronize do
            result = {}
            keys.each do |key|
              if @data.key?(key)
                if @ttl_enabled && expired?(key)
                  @data.delete(key)
                  @ttl_data.delete(key)
                  result[key] = nil
                else
                  result[key] = @data[key]
                end
              else
                result[key] = nil
              end
            end
            result
          end
        end

        def bulk_delete(keys)
          @mutex.synchronize do
            result = {}
            keys.each do |key|
              result[key] = @data.delete(key)
              @ttl_data.delete(key) if @ttl_enabled
            end
            result
          end
        end

        private

        def expired?(key)
          return false unless @ttl_enabled
          return false unless @ttl_data.key?(key)

          Time.now > @ttl_data[key]
        end

        def count_expired_keys
          return 0 unless @ttl_enabled

          count = 0
          @ttl_data.each_value do |expiry_time|
            count += 1 if Time.now > expiry_time
          end
          count
        end
      end
    end
  end
end
