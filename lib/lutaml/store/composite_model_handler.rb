# frozen_string_literal: true

module Lutaml
  module Store
    class CompositeModelHandler
      Reference = Struct.new(:storage_key, :model_class, :key_value, keyword_init: true)

      def initialize(registry, store, model_store = nil, serializer:)
        @registry = registry
        @store = store
        @model_store = model_store
        @serializer = serializer
      end

      def process_composite_models(model)
        composite_models = @registry.find_composite_models(model)
        stored_composites = {}

        composite_models.each do |attr_path, composite_info|
          nested_model = composite_info[:model]
          registration = composite_info[:registration]

          storage_key = registration.generate_storage_key(nested_model)
          serialized_data = @serializer.serialize(nested_model)
          @store.set(storage_key, serialized_data)

          stored_composites[attr_path] = Reference.new(
            storage_key: storage_key.to_s,
            model_class: nested_model.class.name,
            key_value: composite_info[:key_value]
          )
        end

        stored_composites
      end

      def restore_composite_models(model, composite_references = nil)
        return model unless composite_references

        restored_model = model.dup

        composite_references.each do |attr_path, reference_info|
          ref = if reference_info.is_a?(Hash)
                  Reference.new(**reference_info.transform_keys(&:to_sym).slice(
                    :storage_key, :model_class, :key_value
                  ))
                else
                  reference_info
                end
          nested_model = restore_nested_model(ref)
          next unless nested_model

          set_nested_attribute(restored_model, attr_path, nested_model)
        end

        restored_model
      end

      def update_composite_models(model, updates)
        composite_updates = extract_composite_updates(updates)
        return if composite_updates.empty?

        composite_updates.each do |attr_path, update_value|
          if attr_path.include?(".")
            update_nested_composite(model, attr_path, update_value)
          else
            update_direct_composite(model, attr_path, update_value)
          end
        end
      end

      def delete_composite_models(model)
        composite_models = @registry.find_composite_models(model)

        composite_models.each_value do |composite_info|
          registration = composite_info[:registration]
          storage_key = registration.generate_storage_key(composite_info[:model])
          @store.delete(storage_key)
        end
      end

      private

      def restore_nested_model(reference)
        storage_key = reference.storage_key
        model_class_name = reference.model_class
        key_value = reference.key_value

        if @model_store && key_value
          model_class = Object.const_get(model_class_name)
          registration = @registry.find_registration(model_class)
          if registration
            key_field = registration.key_field
            return @model_store.fetch(model: model_class, key_field => key_value)
          end
        end

        serialized_data = @store.get(storage_key)
        return nil unless serialized_data

        model_class = Object.const_get(model_class_name)
        @serializer.deserialize(serialized_data, model_class)
      end

      def set_nested_attribute(model, attr_path, value)
        attr_path_str = attr_path.to_s
        if attr_path_str.include?(".")
          parts = attr_path_str.split(".")
          current = navigate_to_parent(model, parts[0..-2])
          set_final_attribute(current, parts.last, value)
        else
          model.public_send("#{attr_path}=", value)
        end
      end

      def navigate_to_parent(model, path_parts)
        path_parts.reduce(model) do |current, part|
          if part.match?(/\A\d+\z/)
            current[part.to_i]
          else
            current.public_send(part)
          end
        end
      end

      def set_final_attribute(current, attr, value)
        if attr.match?(/\A\d+\z/)
          current[attr.to_i] = value
        else
          current.public_send("#{attr}=", value)
        end
      end

      def extract_composite_updates(updates)
        updates.each_with_object({}) do |update, result|
          key = update[:key].to_s
          value = update[:value]
          result[key] = value if key.include?(".") || registered_model?(value)
        end
      end

      def update_nested_composite(model, attr_path, update_value)
        root_attr = attr_path.split(".").first
        composite_model = model.public_send(root_attr)
        return unless composite_model && @registry.registered?(composite_model.class)

        set_nested_attribute(composite_model, attr_path.split(".", 2).last, update_value)

        registration = @registry.registration_for(composite_model.class)
        storage_key = registration.generate_storage_key(composite_model)
        @store.set(storage_key, @serializer.serialize(composite_model))
      end

      def update_direct_composite(model, attr_path, new_composite_model)
        return unless registered_model?(new_composite_model)

        registration = @registry.registration_for(new_composite_model.class)
        storage_key = registration.generate_storage_key(new_composite_model)
        @store.set(storage_key, @serializer.serialize(new_composite_model))

        model.public_send("#{attr_path}=", new_composite_model)
      end

      def registered_model?(value)
        value.is_a?(Object) && @registry.registered?(value.class)
      end
    end
  end
end
