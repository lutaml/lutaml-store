# frozen_string_literal: true

module Lutaml
  module Store
    module Format
      class MarshalFormat < Base
        def extension
          ".bin"
        end

        def glob_pattern
          "*.bin"
        end

        def serialize(model)
          hash_data = model.to_hash
          ::Marshal.dump(hash_data)
        end

        def deserialize(data, model_class)
          hash_data = ::Marshal.load(data)
          model_class.from_hash(hash_data)
        end

        def serialize_many(models)
          hash_array = models.map(&:to_hash)
          ::Marshal.dump(hash_array)
        end

        def deserialize_many(data, model_class)
          hash_array = ::Marshal.load(data)
          hash_array.map { |h| model_class.from_hash(h) }
        end
      end
    end
  end
end
