# frozen_string_literal: true

module Lutaml
  module Store
    module Adapter
      class Base
        def initialize(config = {})
          @config = config
        end

        # ── Key-value operations ──

        def get(key)
          raise NotImplementedError
        end

        def set(key, value)
          raise NotImplementedError
        end

        def delete(key)
          raise NotImplementedError
        end

        def exists?(key)
          raise NotImplementedError
        end

        def keys
          raise NotImplementedError
        end

        def each_key(&block)
          raise NotImplementedError
        end

        def all
          raise NotImplementedError
        end

        def clear
          raise NotImplementedError
        end

        def size
          raise NotImplementedError
        end

        def close
          # Optional — override in subclasses that hold resources
        end

        def bulk_get(keys)
          keys.each_with_object({}) { |k, h| h[k] = get(k) }
        end

        def bulk_set(key_value_pairs)
          key_value_pairs.each { |k, v| set(k, v) }
        end

        def bulk_delete(keys)
          keys.each_with_object({}) { |k, h| h[k] = delete(k) }
        end

        # ── Query operations ──

        # Execute a query specification.
        # Returns array of [storage_key, hash_data] pairs, sorted and paginated.
        # Returns nil to indicate "not supported — fall back to in-memory scan".
        def execute_query(_query)
          nil
        end

        # Count matching records without returning data.
        # Returns nil to indicate "not supported — count execute_query results".
        def count_query(_query)
          nil
        end

        # Fetch a batch of [storage_key, hash_data] pairs for keyset pagination.
        # Returns nil to indicate "not supported — fall back to in-memory".
        def batch_query(_query, _after: nil, _limit: 1000)
          nil
        end

        # Execute a block atomically. No-op for adapters without transaction support.
        def transaction
          yield
        end

        def stats
          { adapter: self.class.name }
        end
      end
    end
  end
end
