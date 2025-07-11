# frozen_string_literal: true

require_relative "../integrity"

module Lutaml
  module Store
    module Adapter
      class Base
        def initialize(config = {})
          @config = config
          @integrity_enabled = config.fetch(:integrity_checks, true)
          @integrity_algorithm = config.fetch(:integrity_algorithm, "sha256")
        end

        def save(key, data, metadata = {})
          raise NotImplementedError, "Subclasses must implement #save"
        end

        def load(key)
          raise NotImplementedError, "Subclasses must implement #load"
        end

        def delete(key)
          raise NotImplementedError, "Subclasses must implement #delete"
        end

        def exists?(key)
          raise NotImplementedError, "Subclasses must implement #exists?"
        end

        def keys
          raise NotImplementedError, "Subclasses must implement #keys"
        end

        def clear
          raise NotImplementedError, "Subclasses must implement #clear"
        end

        def size
          raise NotImplementedError, "Subclasses must implement #size"
        end

        def close
          # Default implementation - subclasses can override if needed
        end

        def verify_integrity
          raise NotImplementedError, "Subclasses must implement #verify_integrity"
        end

        def repair_corruption(key, backup_data = nil)
          raise NotImplementedError, "Subclasses must implement #repair_corruption"
        end

        protected

        attr_reader :config, :integrity_enabled, :integrity_algorithm

        def create_integrity_metadata(data)
          return {} unless integrity_enabled
          Integrity.create_integrity_metadata(data, integrity_algorithm)
        end

        def verify_data_integrity(data, metadata)
          return true unless integrity_enabled
          return true unless metadata.is_a?(Hash) && metadata[:integrity]

          Integrity.verify_integrity_metadata(data, metadata[:integrity])
        end

        def wrap_with_integrity(data, user_metadata = {})
          metadata = user_metadata.dup
          metadata[:integrity] = create_integrity_metadata(data) if integrity_enabled
          metadata
        end

        def extract_user_metadata(metadata)
          return metadata unless metadata.is_a?(Hash)
          metadata.reject { |k, _| k == :integrity }
        end
      end
    end
  end
end
