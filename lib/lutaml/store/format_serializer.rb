# frozen_string_literal: true

module Lutaml
  module Store
    # Bridges a Format handler to the ModelSerializer interface.
    # Enables DatabaseStore to use any format (yaml, json, xml, yamls, marshal)
    # for key-value storage instead of the default hash serialization.
    #
    # Usage:
    #   serializer = FormatSerializer.new(:yamls)
    #   store = DatabaseStore.new(
    #     adapter: :sqlite,
    #     models: [{ model: ConceptDocument, key: :id, serializer: serializer }]
    #   )
    class FormatSerializer
      DATA_KEY = "_data"
      CLASS_KEY = "_class"

      def initialize(format)
        @format = Format.resolve(format)
      end

      def serialize(model)
        {
          DATA_KEY => @format.serialize(model),
          CLASS_KEY => model.class.name
        }
      end

      def deserialize(data, model_class)
        model_class = resolve_class(data[CLASS_KEY]) if data[CLASS_KEY]
        @format.deserialize(data[DATA_KEY], model_class)
      end

      private

      def resolve_class(class_name)
        Object.const_get(class_name)
      rescue NameError
        nil
      end
    end
  end
end
