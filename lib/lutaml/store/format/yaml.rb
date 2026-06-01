# frozen_string_literal: true

module Lutaml
  module Store
    module Format
      class Yaml < Base
        def extension
          ".yaml"
        end

        def glob_pattern
          "*.{yaml,yml}"
        end

        def serialize(model)
          model.to_yaml
        end

        def deserialize(data, model_class)
          model_class.from_yaml(data)
        end

        def deserialize_many(data, model_class)
          model_class.from_yamls(data)
        end
      end
    end
  end
end
