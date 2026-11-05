# frozen_string_literal: true

module Lutaml
  module Store
    module Adapter
      # Wraps a backend adapter so records registered as MirrorRefs answer
      # reads with their live models — no serialization, no backend write.
      # With mirrors present, native query execution reports unsupported so
      # the store's fallback scan (which walks keys and therefore sees
      # mirrors) runs instead. set/delete on a mirror key clears the mirror
      # and delegates; the backend remains the single writer.
      class MirrorAware < Base
        attr_reader :backend

        def self.wrap(backend)
          new(backend)
        end

        def initialize(backend)
          super()
          @backend = backend
          @mirrors = {}
          @models = {}
        end

        def register_mirror(ref)
          @mirrors[ref.storage_key] = ref
          @models.delete(ref.storage_key)
          ref
        end

        def mirror_count
          @mirrors.size
        end

        def get(key)
          ref = @mirrors[key]
          return @backend.get(key) unless ref

          @models[key] ||= ref.reader.call
        end

        def set(key, value)
          @mirrors.delete(key)
          @models.delete(key)
          @backend.set(key, value)
        end

        def delete(key)
          @mirrors.delete(key)
          @models.delete(key)
          @backend.delete(key)
        end

        def exists?(key)
          @mirrors.key?(key) || @backend.exists?(key)
        end

        def keys
          (@backend.keys + @mirrors.keys).uniq
        end

        def size
          keys.size
        end

        def all
          records = @backend.all

          @mirrors.each_key { |key| records[key] = get(key) }
          records
        end

        def clear
          @mirrors.clear
          @models.clear
          @backend.clear
        end

        def close
          @backend.close
        end

        def transaction(&block)
          @backend.transaction(&block)
        end

        # Native query execution sees only backend records; with mirrors
        # present, report unsupported so the store's fallback scan (which
        # walks keys and therefore includes mirrors) runs instead.
        def execute_query(query)
          return @backend.execute_query(query) if @mirrors.empty?

          nil
        end

        def count_query(query)
          return @backend.count_query(query) if @mirrors.empty?

          nil
        end

        def batch_query(query, after: nil, limit: 1000)
          return @backend.batch_query(query, after: after, limit: limit) if @mirrors.empty?

          nil
        end
      end
    end
  end
end
