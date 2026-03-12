# frozen_string_literal: true

module Lutaml
  module Store
    # Handles relationships between registered models, storing composite models independently
    class CompositeModelHandler
      def initialize(registry, store, model_store = nil)
        @registry = registry
        @store = store
        @model_store = model_store
      end

      # Process and store composite models independently
      def process_composite_models(model)
        composite_models = @registry.find_composite_models(model)
        stored_composites = {}

        composite_models.each do |attr_path, composite_info|
          nested_model = composite_info[:model]
          registration = composite_info[:registration]

          # Store the nested model independently
          storage_key = registration.generate_storage_key(nested_model)
          serialized_data = serialize_model(nested_model)
          @store.set(storage_key, serialized_data)

          # Track what was stored
          stored_composites[attr_path] = {
            storage_key: storage_key,
            model_class: nested_model.class.name,
            key_value: composite_info[:key_value]
          }
        end

        stored_composites
      end

      # Restore composite models from storage
      def restore_composite_models(model, composite_references = nil)
        return model unless composite_references

        restored_model = model.dup

        composite_references.each do |attr_path, reference_info|
          storage_key = reference_info[:storage_key]
          model_class_name = reference_info[:model_class]
          key_value = reference_info[:key_value]

          # Try to use ModelStore's polymorphic fetch if available
          nested_model = if @model_store && key_value
                           model_class = Object.const_get(model_class_name)
                           registration = @registry.find_registration(model_class)
                           if registration
                             key_field = registration.key_field
                             @model_store.fetch(model: model_class, key_field => key_value)
                           else
                             fallback_restore(storage_key, model_class_name)
                           end
                         else
                           fallback_restore(storage_key, model_class_name)
                         end

          next unless nested_model

          # Set the nested model on the restored model
          set_nested_attribute(restored_model, attr_path, nested_model)
        end

        restored_model
      end

      # Update composite models when parent model is updated
      def update_composite_models(model, updates)
        composite_updates = extract_composite_updates(updates)
        return if composite_updates.empty?

        composite_updates.each do |attr_path, update_value|
          if attr_path.include?(".")
            # Handle nested attribute updates like "studio.location"
            update_nested_composite(model, attr_path, update_value)
          else
            # Handle direct composite model replacement
            update_direct_composite(model, attr_path, update_value)
          end
        end
      end

      # Delete composite models when parent is deleted
      def delete_composite_models(model)
        composite_models = @registry.find_composite_models(model)

        composite_models.each do |attr_path, composite_info|
          registration = composite_info[:registration]
          storage_key = registration.generate_storage_key(composite_info[:model])
          @store.delete(storage_key)
        end
      end

      private

      def serialize_model(model)
        if model.respond_to?(:to_hash)
          hash_data = model.to_hash
          if hash_data.is_a?(Hash)
            hash_data.merge("_class" => model.class.name)
          else
            { "_class" => model.class.name, "_data" => model.to_s }
          end
        elsif model.respond_to?(:to_h)
          hash_data = model.to_h
          if hash_data.is_a?(Hash)
            hash_data.merge("_class" => model.class.name)
          else
            { "_class" => model.class.name, "_data" => model.to_s }
          end
        else
          { "_class" => model.class.name, "_data" => model.to_s }
        end
      end

      def deserialize_model(data, expected_class)
        unless data.is_a?(Hash) && data["_class"]
          raise CompositeModelError, "Invalid serialized data for #{expected_class}"
        end

        model_class = Object.const_get(data["_class"])
        model_data = data.except("_class", "_composite_models")

        if model_class.respond_to?(:from_hash)
          model_class.from_hash(model_data)
        elsif model_class.respond_to?(:from_h)
          model_class.from_h(model_data)
        elsif model_class.respond_to?(:new)
          model_class.new(model_data)
        else
          raise CompositeModelError, "Cannot deserialize #{model_class}"
        end
      end

      def set_nested_attribute(model, attr_path, value)
        attr_path_str = attr_path.to_s
        if attr_path_str.include?(".")
          # Handle nested paths like "studio.location"
          parts = attr_path.split(".")
          current = model

          # Navigate to the parent of the target attribute
          parts[0..-2].each do |part|
            current = if part.match?(/\A\d+\z/)
                        # Array index
                        current[part.to_i]
                      else
                        # Attribute name
                        current.public_send(part)
                      end
          end

          # Set the final attribute
          final_attr = parts.last
          if final_attr.match?(/\A\d+\z/)
            current[final_attr.to_i] = value
          else
            current.public_send("#{final_attr}=", value)
          end
        else
          # Direct attribute
          model.public_send("#{attr_path}=", value)
        end
      end

      def extract_composite_updates(updates)
        composite_updates = {}

        updates.each do |update|
          key = update[:key]
          value = update[:value]

          # Check if this update affects a composite model
          composite_updates[key.to_s] = value if key.to_s.include?(".") || is_registered_model?(value)
        end

        composite_updates
      end

      def update_nested_composite(model, attr_path, update_value)
        # Get the composite model that contains the nested attribute
        root_attr = attr_path.split(".").first
        composite_model = model.public_send(root_attr)

        return unless composite_model && @registry.registered?(composite_model.class)

        # Update the nested attribute
        set_nested_attribute(composite_model, attr_path.split(".", 2).last, update_value)

        # Re-store the updated composite model
        registration = @registry.registration_for(composite_model.class)
        storage_key = registration.generate_storage_key(composite_model)
        serialized_data = serialize_model(composite_model)
        @store.set(storage_key, serialized_data)
      end

      def update_direct_composite(model, attr_path, new_composite_model)
        return unless is_registered_model?(new_composite_model)

        # Store the new composite model
        registration = @registry.registration_for(new_composite_model.class)
        storage_key = registration.generate_storage_key(new_composite_model)
        serialized_data = serialize_model(new_composite_model)
        @store.set(storage_key, serialized_data)

        # Update the reference in the parent model
        model.public_send("#{attr_path}=", new_composite_model)
      end

      def is_registered_model?(value)
        value.is_a?(Object) && @registry.registered?(value.class)
      end

      def fallback_restore(storage_key, model_class_name)
        # Fallback to direct storage access
        serialized_data = @store.get(storage_key)
        return nil unless serialized_data

        model_class = Object.const_get(model_class_name)
        deserialize_model(serialized_data, model_class)
      end
    end
  end
end
