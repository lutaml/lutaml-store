# frozen_string_literal: true

module Lutaml
  module Store
    module Format
      class Xml < Base
        def extension
          ".xml"
        end

        def glob_pattern
          "*.xml"
        end

        def serialize(model)
          model.to_xml
        end

        def deserialize(data, model_class)
          model_class.from_xml(data)
        end

        def serialize_many(models)
          inner = models.map(&:to_xml).join("\n")
          "<items>\n#{inner}\n</items>"
        end

        def deserialize_many(data, model_class)
          doc = Moxml.parse(data)
          doc.root.children.select(&:element?).map do |child|
            model_class.from_xml(child.to_xml)
          end
        end
      end
    end
  end
end
