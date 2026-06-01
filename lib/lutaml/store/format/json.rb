# frozen_string_literal: true

module Lutaml
  module Store
    module Format
      class Json < Base
        def extension
          ".json"
        end

        def glob_pattern
          "*.json"
        end

        def serialize(model)
          model.to_json
        end

        def deserialize(data, model_class)
          model_class.from_json(data)
        end
      end
    end
  end
end
