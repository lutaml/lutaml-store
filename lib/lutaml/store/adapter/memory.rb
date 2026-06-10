# frozen_string_literal: true

module Lutaml
  module Store
    module Adapter
      # In-memory key-value adapter optimized for read-heavy workloads.
      # Writes are synchronized; reads are lock-free using snapshot copies.
      class Memory < Base
        def initialize(config = {})
          super
          @data = {}
          @write_mutex = Mutex.new
          @read_snapshot = {}.freeze
          @snapshot_stale = true
          @ttl_enabled = @config.fetch(:ttl_enabled, false)
          @ttl_data = @ttl_enabled ? {} : nil
          @default_ttl = @config[:default_ttl] || 3600
        end

        # ── Read operations (lock-free via snapshot) ──

        def get(key)
          cleanup_expired_if_needed
          snapshot[key]
        end

        def exists?(key)
          cleanup_expired_if_needed
          snapshot.key?(key)
        end

        def all
          cleanup_expired_if_needed
          snapshot.dup
        end

        def size
          cleanup_expired_if_needed
          snapshot.size
        end

        def keys
          cleanup_expired_if_needed
          snapshot.keys
        end

        def each_key(&block)
          cleanup_expired_if_needed
          snapshot.each_key(&block)
        end

        def bulk_get(keys)
          cleanup_expired_if_needed
          snap = snapshot
          keys.each_with_object({}) do |k, h|
            h[k] = snap[k]
          end
        end

        # ── Write operations (synchronized) ──

        def set(key, value, metadata = {})
          @write_mutex.synchronize do
            @data[key] = value
            invalidate_snapshot

            if @ttl_enabled
              ttl_value = metadata[:ttl] || @default_ttl
              @ttl_data[key] = Time.now + ttl_value if ttl_value
            end
          end
          value
        end

        def delete(key)
          @write_mutex.synchronize do
            existed = @data.key?(key)
            @data.delete(key)
            @ttl_data&.delete(key)
            invalidate_snapshot
            existed
          end
        end

        def clear
          @write_mutex.synchronize do
            count = @data.size
            @data.clear
            @ttl_data&.clear
            invalidate_snapshot
            count
          end
        end

        def close
          @write_mutex.synchronize do
            @data.clear
            @ttl_data&.clear
            invalidate_snapshot
          end
        end

        def bulk_set(key_value_pairs, ttl: nil)
          @write_mutex.synchronize do
            key_value_pairs.each do |key, value|
              @data[key] = value

              if @ttl_enabled
                ttl_value = ttl || @default_ttl
                @ttl_data[key] = Time.now + ttl_value if ttl_value
              end
            end
            invalidate_snapshot
          end
        end

        def bulk_delete(keys)
          @write_mutex.synchronize do
            result = {}
            keys.each do |key|
              result[key] = @data.delete(key)
              @ttl_data&.delete(key)
            end
            invalidate_snapshot
            result
          end
        end

        # ── TTL operations ──

        def cleanup_expired
          return unless @ttl_enabled

          @write_mutex.synchronize do
            now = Time.now
            expired_keys = @ttl_data.each_with_object([]) do |(key, expiry_time), arr|
              arr << key if now > expiry_time
            end

            expired_keys.each do |key|
              @data.delete(key)
              @ttl_data.delete(key)
            end
            invalidate_snapshot unless expired_keys.empty?
            expired_keys.size
          end
        end

        def set_ttl(key, ttl)
          return false unless @ttl_enabled

          @write_mutex.synchronize do
            return false unless @data.key?(key)

            if ttl
              @ttl_data[key] = Time.now + ttl
            else
              @ttl_data.delete(key)
            end
            invalidate_snapshot
            true
          end
        end

        def get_ttl(key)
          return nil unless @ttl_enabled

          snap = snapshot
          return nil unless snap.key?(key)
          return nil unless @ttl_data.key?(key)

          remaining = @ttl_data[key] - Time.now
          remaining.positive? ? remaining : nil
        end

        # ── Query operations (lock-free via snapshot) ──

        def execute_query(query)
          cleanup_expired_if_needed
          snap = snapshot
          model_name = query.model_class.name
          preds = query.predicates

          results = []
          snap.each do |key, value|
            parsed = StorageKey.parse(key.to_s)
            next unless parsed.class_name == model_name
            next unless preds_all_match?(preds, value)

            results << [key, value]
          end

          results = apply_sort(results, query.orders)
          results = apply_pagination(results, query.limit_value, query.offset_value)
        end

        def count_query(query)
          cleanup_expired_if_needed
          snap = snapshot
          model_name = query.model_class.name
          preds = query.predicates

          count = 0
          snap.each do |key, value|
            parsed = StorageKey.parse(key.to_s)
            next unless parsed.class_name == model_name
            next unless preds_all_match?(preds, value)

            count += 1
          end
          count
        end

        def batch_query(query, after: nil, limit: 1000)
          cleanup_expired_if_needed
          snap = snapshot
          model_name = query.model_class.name
          preds = query.predicates

          sorted_keys = snap.keys.sort_by(&:to_s)
          sorted_keys = sorted_keys.select { |k| k.to_s > after } if after

          results = []
          sorted_keys.each do |key|
            parsed = StorageKey.parse(key.to_s)
            next unless parsed.class_name == model_name

            value = snap[key]
            next unless value
            next unless preds_all_match?(preds, value)

            results << [key.to_s, value]
            break if results.size >= limit
          end
          results
        end

        def stats
          cleanup_expired_if_needed
          snap = snapshot
          super.merge(
            size: snap.size,
            ttl_enabled: @ttl_enabled,
            expired_keys: @ttl_enabled ? count_expired_keys : 0
          )
        end

        private

        # Frozen snapshot — lock-free reads. Rebuilt lazily after writes.
        def snapshot
          if @snapshot_stale
            @write_mutex.synchronize do
              if @snapshot_stale
                @read_snapshot = @data.dup.freeze
                @snapshot_stale = false
              end
            end
          end
          @read_snapshot
        end

        def invalidate_snapshot
          @snapshot_stale = true
        end

        def cleanup_expired_if_needed
          return unless @ttl_enabled

          now = Time.now
          return unless @ttl_data.any? { |_k, expiry| now > expiry }

          cleanup_expired
        end

        def count_expired_keys
          return 0 unless @ttl_enabled

          now = Time.now
          @ttl_data.count { |_k, expiry| now > expiry }
        end

        # Inline predicate evaluation — avoids method dispatch overhead in tight loops
        def preds_all_match?(predicates, value)
          predicates.all? { |p| p.match?(value) }
        end

        def apply_sort(results, orders)
          return results if orders.empty?

          results.sort do |a, b|
            orders.reduce(0) do |cmp, o|
              break cmp unless cmp.zero?

              va = a.last.is_a?(Hash) ? a.last[o.field.to_s] : nil
              vb = b.last.is_a?(Hash) ? b.last[o.field.to_s] : nil

              cmp_val = compare_values(va, vb)
              o.direction == :desc ? -cmp_val : cmp_val
            end
          end
        end

        def compare_values(val_a, val_b)
          if val_a.nil? && val_b.nil?
            0
          elsif val_a.nil?
            1
          elsif val_b.nil?
            -1
          else
            val_a <=> val_b || 0
          end
        end

        def apply_pagination(results, limit, offset)
          start = offset || 0
          results = results[start..] || []
          results = results.first(limit) if limit
          results
        end
      end
    end
  end
end
