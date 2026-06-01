# frozen_string_literal: true

module Lutaml
  module Store
    # Single point of serialization/deserialization for Lutaml::Model objects.
    # All registered models are Lutaml::Model::Serializable, so they uniformly
    # support to_hash / from_hash. No duck-typing needed.
    class ModelSerializer
      METADATA_KEY = "_class"
      COMPOSITE_KEY = "_composite_models"

      def serialize(model, registration = nil)
        hash_data = if registration&.serializer
                      registration.serializer.serialize(model)
                    else
                      extract_hash(model)
                    end
        hash_data.merge(METADATA_KEY => model.class.name)
      end

      def deserialize(data, expected_class, registration = nil)
        validate_data!(data, expected_class)

        model_class = resolve_class(data[METADATA_KEY])
        validate_polymorphic_compatibility!(model_class, expected_class)

        model_data = data.except(METADATA_KEY, COMPOSITE_KEY)
        if registration&.serializer
          registration.serializer.deserialize(model_data, model_class)
        else
          build_model(model_class, model_data)
        end
      end

      private

      def extract_hash(model)
        model.to_hash
      rescue NoMethodError
        model.to_h
      end

      def build_model(model_class, data)
        model_class.from_hash(data)
      rescue NoMethodError
        model_class.from_h(data)
      end

      def validate_data!(data, expected_class)
        return if data.is_a?(Hash) && data[METADATA_KEY]

        raise CompositeModelError, "Invalid serialized data for #{expected_class}"
      end

      def resolve_class(class_name)
        Object.const_get(class_name)
      rescue NameError
        raise CompositeModelError, "Cannot resolve class #{class_name}"
      end

      def validate_polymorphic_compatibility!(model_class, expected_class)
        return if model_class <= expected_class

        raise PolymorphicUpdateError,
              "Stored #{model_class} is not compatible with #{expected_class}"
      end
    end
  end
end
