# frozen_string_literal: true

module Lutaml
  module Store
    module Format
      class Jsonl < Base
        def extension
          ".jsonl"
        end

        def glob_pattern
          "*.jsonl"
        end

        def serialize(model)
          model.to_json
        end

        def serialize_many(models)
          "#{models.map(&:to_json).join("\n")}\n"
        end

        def deserialize(data, model_class)
          model_class.from_json(data)
        end

        def deserialize_many(data, model_class)
          data.lines.filter_map do |line|
            next if line.strip.empty?

            model_class.from_json(line)
          end
        end
      end
    end
  end
end
