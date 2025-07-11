# frozen_string_literal: true

require "thread"

module Lutaml
  module Store
    module Backend
      class Memory < Base
        def initialize(options = {})
          super
          @data = {}
          @mutex = Mutex.new
        end

        def get(key)
          @mutex.synchronize { @data[key] }
        end

        def set(key, value)
          @mutex.synchronize { @data[key] = value }
        end

        def delete(key)
          @mutex.synchronize { !@data.delete(key).nil? }
        end

        def exists?(key)
          @mutex.synchronize { @data.key?(key) }
        end

        def all
          @mutex.synchronize { @data.dup }
        end

        def clear
          @mutex.synchronize { @data.clear }
        end

        def size
          @mutex.synchronize { @data.size }
        end

        def keys
          @mutex.synchronize { @data.keys }
        end

        def values
          @mutex.synchronize { @data.values }
        end
      end
    end
  end
end
