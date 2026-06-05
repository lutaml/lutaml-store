# frozen_string_literal: true

module Lutaml
  module Store
    module Format
      class Yamls < Base
        def extension
          ".yaml"
        end

        def glob_pattern
          "*.{yaml,yml}"
        end

        def serialize(model)
          model.to_yamls
        end

        def serialize_many(models)
          models.map(&:to_yamls).join("\n")
        end

        def deserialize(data, model_class)
          docs = model_class.from_yamls(data)
          docs.is_a?(Array) ? docs.first : docs
        end

        def deserialize_many(data, model_class)
          result = model_class.from_yamls(data)
          result.is_a?(Array) ? result : [result]
        end
      end
    end
  end
end
