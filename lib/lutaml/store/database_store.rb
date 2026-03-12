# frozen_string_literal: true

require_relative "store"
require_relative "serializer"
require_relative "compression"
require_relative "model_registry"
require_relative "composite_model_handler"
require_relative "attribute_updater"

module Lutaml
  module Store
    # New store-centric API with model registry and database-style operations
    class DatabaseStore
      attr_reader :store, :registry, :composite_handler, :attribute_updater

      def initialize(adapter:, models: [], **options)
        # Initialize the underlying store
        store_config = { adapter_type: adapter }.merge(options)
        @store = Store.new(store_config)

        # Initialize the model registry
        @registry = ModelRegistry.new(models)

        # Initialize composite model handler
        @composite_handler = CompositeModelHandler.new(@registry, @store, self)

        # Initialize attribute updater
        @attribute_updater = AttributeUpdater.new(@registry, @composite_handler)

        # Validate configuration
        validate_configuration!
      end

      # Save single model or array of models
      def save(models)
        models_array = Array(models)
        saved_models = []

        models_array.each do |model|
          saved_model = save_single_model(model)
          saved_models << saved_model
        end

        emit_event(:model_save, models: saved_models, count: saved_models.size)
        models.is_a?(Array) ? saved_models : saved_models.first
      end

      # Fetch model by class and key field
      def fetch(model:, **key_params)
        registration = @registry.registration_for(model)

        # Extract key value from parameters
        key_field = registration.key_field
        key_value = key_params[key_field]

        raise InvalidKeyError, "Key field '#{key_field}' not provided" if key_value.nil?

        # For polymorphic models, try to find the most specific stored version
        stored_data = nil
        storage_key = nil

        if registration.polymorphic?
          # Try to find any polymorphic variant of this model, preferring more specific classes
          matching_candidates = []

          @store.keys.each do |key|
            next unless key.end_with?(":#{key_value}")

            candidate_data = @store.get(key)
            next unless candidate_data&.dig("_class")

            # Check if the stored class is compatible with the requested model
            stored_class = Object.const_get(candidate_data["_class"])
            next unless stored_class <= model

            matching_candidates << {
              key: key,
              data: candidate_data,
              class: stored_class
            }
          end

          # Sort by inheritance hierarchy - more specific classes first
          matching_candidates.sort! do |a, b|
            if a[:class] <= b[:class] && b[:class] <= a[:class]
              0 # Same class
            elsif a[:class] < b[:class]
              -1 # a is more specific
            else
              1 # b is more specific
            end
          end

          # Use the most specific match
          if matching_candidates.any?
            best_match = matching_candidates.first
            stored_data = best_match[:data]
            storage_key = best_match[:key]
          end
        else
          # Non-polymorphic lookup
          storage_key = registration.generate_storage_key_from_value(key_value)
          stored_data = @store.get(storage_key)
        end

        return nil unless stored_data

        # Deserialize model
        model_instance = deserialize_model(stored_data, model)

        # Restore composite models
        composite_references = stored_data["_composite_models"]
        if composite_references
          model_instance = @composite_handler.restore_composite_models(
            model_instance,
            composite_references
          )
        end

        emit_event(:model_fetch, model: model_instance, key: key_value, source: :backend)
        model_instance
      end

      # Update model with attributes array or block
      def update(model:, attributes: nil, **key_params, &block)
        # Fetch the current model
        current_model = fetch(model: model, **key_params)
        raise ModelNotRegisteredError, "Model not found" unless current_model

        # Apply updates
        updated_model = if block_given?
                          @attribute_updater.update_with_block(current_model, &block)
                        elsif attributes
                          if attributes.is_a?(Hash)
                            @attribute_updater.update_with_hash(current_model, attributes)
                          else
                            @attribute_updater.update_with_attributes(current_model, attributes)
                          end
                        else
                          raise ArgumentError, "Either attributes or block must be provided"
                        end

        # Save the updated model
        save(updated_model)

        emit_event(:model_update,
                   model: updated_model,
                   key: key_params,
                   changes: extract_changes(current_model, updated_model))

        updated_model
      end

      # Destroy model by class and key field
      def destroy(model:, **key_params)
        registration = @registry.registration_for(model)

        # Extract key value from parameters
        key_field = registration.key_field
        key_value = key_params[key_field]

        raise InvalidKeyError, "Key field '#{key_field}' not provided" if key_value.nil?

        # Fetch model before deletion for composite cleanup
        model_instance = fetch(model: model, **key_params)
        return false unless model_instance

        # Delete composite models
        @composite_handler.delete_composite_models(model_instance)

        # Generate storage key and delete
        storage_key = registration.generate_storage_key_from_value(key_value)
        deleted = @store.delete(storage_key)

        emit_event(:model_destroy, model: model, key: key_value, deleted: deleted)
        deleted
      end

      # Query operations (basic implementation)
      def where(model:, **conditions)
        # Basic implementation - can be enhanced with indexing
        all_models = all(model: model)

        all_models.select do |model_instance|
          conditions.all? do |field, value|
            model_instance.public_send(field) == value
          end
        end
      end

      # Get all models of a specific type
      def all(model:)
        registration = @registry.registration_for(model)
        model_prefix = "#{model.name}:"

        models = []
        @store.keys.each do |storage_key|
          next unless storage_key.start_with?(model_prefix)

          stored_data = @store.get(storage_key)
          next unless stored_data

          begin
            model_instance = deserialize_model(stored_data, model)

            # Restore composite models
            composite_references = stored_data["_composite_models"]
            if composite_references
              model_instance = @composite_handler.restore_composite_models(
                model_instance,
                composite_references
              )
            end

            models << model_instance
          rescue StandardError => e
            emit_event(:deserialization_error, key: storage_key, error: e)
          end
        end

        models
      end

      # Check if model exists
      def exists?(model:, **key_params)
        !fetch(model: model, **key_params).nil?
      end

      # Count models of a specific type
      def count(model:)
        all(model: model).size
      end

      # Event handling
      def on(event, &block)
        @store.on(event, &block)
      end

      def off(event, listener)
        @store.off(event, listener)
      end

      # Statistics and monitoring
      def stats
        base_stats = @store.stats || {}
        base_stats.merge({
                           models_registered: @registry.count,
                           registered_models: @registry.registered_models.map(&:name),
                           total_models: total_model_count
                         })
      end

      # Resource management
      def close
        @store.close
      end

      private

      def save_single_model(model)
        registration = @registry.registration_for(model.class)

        # Process composite models first
        composite_references = @composite_handler.process_composite_models(model)

        # Serialize the main model
        serialized_data = serialize_model(model)

        # Add composite model references
        serialized_data["_composite_models"] = composite_references unless composite_references.empty?

        # Generate storage key
        storage_key = registration.generate_storage_key(model)

        # Store in backend
        @store.set(storage_key, serialized_data)

        unless composite_references.empty?
          emit_event(:composite_model_stored,
                     model: model,
                     composite_count: composite_references.size)
        end

        model
      end

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

        model_class_name = data["_class"]
        model_class = Object.const_get(model_class_name)

        # Validate polymorphic compatibility
        unless model_class <= expected_class
          raise PolymorphicUpdateError,
                "Stored model #{model_class} is not compatible with requested #{expected_class}"
        end

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

      def extract_changes(old_model, new_model)
        changes = {}

        # Basic change detection - can be enhanced
        if old_model.respond_to?(:to_hash) && new_model.respond_to?(:to_hash)
          old_attrs = old_model.to_hash
          new_attrs = new_model.to_hash

          new_attrs.each do |key, new_value|
            old_value = old_attrs[key]
            changes[key] = { from: old_value, to: new_value } if old_value != new_value
          end
        elsif old_model.respond_to?(:to_h) && new_model.respond_to?(:to_h)
          old_attrs = old_model.to_h
          new_attrs = new_model.to_h

          new_attrs.each do |key, new_value|
            old_value = old_attrs[key]
            changes[key] = { from: old_value, to: new_value } if old_value != new_value
          end
        end

        changes
      end

      def total_model_count
        count = 0
        @registry.registered_models.each do |model_class|
          count += count(model: model_class)
        end
        count
      end

      def validate_configuration!
        return unless @registry.empty?

        raise ConfigurationError,
              "No models registered. Provide models: [{ model: YourModel, key: :key_field }]"
      end

      def emit_event(event, data = {})
        @store.instance_variable_get(:@events)&.emit(event, data)
      end
    end
  end
end
