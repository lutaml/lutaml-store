# frozen_string_literal: true

module Lutaml
  module Store
    module Adapter
      class Base
        def initialize(config = {})
          @config = config
        end

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

        def stats
          { adapter: self.class.name }
        end
      end
    end
  end
end
