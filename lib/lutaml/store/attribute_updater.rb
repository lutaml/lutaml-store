# frozen_string_literal: true

module Lutaml
  module Store
    # Processes model updates including dot notation for nested attributes
    class AttributeUpdater
      def initialize(registry, composite_handler)
        @registry = registry
        @composite_handler = composite_handler
      end

      # Update model with attribute array
      def update_with_attributes(model, attributes)
        return model if attributes.nil? || attributes.empty?

        updated_model = model.dup

        attributes.each do |attr_update|
          key = attr_update[:key]
          value = attr_update[:value]

          if key.to_s.include?(".")
            update_nested_attribute(updated_model, key.to_s, value)
          else
            update_direct_attribute(updated_model, key, value)
          end
        end

        # Handle composite model updates
        @composite_handler.update_composite_models(updated_model, attributes)

        updated_model
      end

      # Update model with block
      def update_with_block(model, &block)
        return model unless block_given?

        updated_model = model.dup
        block.call(updated_model)

        # Process any composite models that may have been updated
        composite_models = @registry.find_composite_models(updated_model)
        @composite_handler.process_composite_models(updated_model) unless composite_models.empty?

        updated_model
      end

      # Update model with hash (for backward compatibility)
      def update_with_hash(model, updates_hash)
        return model if updates_hash.nil? || updates_hash.empty?

        attributes = updates_hash.map do |key, value|
          { key: key, value: value }
        end

        update_with_attributes(model, attributes)
      end

      private

      def update_nested_attribute(model, attr_path, value)
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

          raise InvalidKeyError, "Cannot navigate to #{attr_path}: #{part} is nil" if current.nil?
        end

        # Set the final attribute
        final_attr = parts.last
        if final_attr.match?(/\A\d+\z/)
          # Array index assignment
          current[final_attr.to_i] = value
        else
          # Attribute assignment
          setter_method = "#{final_attr}="
          unless current.respond_to?(setter_method)
            raise InvalidKeyError, "No setter method #{setter_method} on #{current.class}"
          end

          current.public_send(setter_method, value)

        end
      end

      def update_direct_attribute(model, attr_name, value)
        setter_method = "#{attr_name}="

        unless model.respond_to?(setter_method)
          # Check if this is a polymorphic case where we need to upgrade the model type
          return if try_polymorphic_upgrade(model, attr_name, value)

          raise InvalidKeyError, "No setter method #{setter_method} on #{model.class}"
        end

        model.public_send(setter_method, value)
      end

      # Validate that the attribute path is valid for the model
      def validate_attribute_path(model, attr_path)
        parts = attr_path.split(".")
        current = model

        parts.each_with_index do |part, index|
          if part.match?(/\A\d+\z/)
            # Array index - check if current is an array
            unless current.is_a?(Array)
              raise InvalidKeyError, "Expected array at #{parts[0..index - 1].join(".")}, got #{current.class}"
            end

            index_val = part.to_i
            if index_val >= current.length
              raise InvalidKeyError, "Array index #{index_val} out of bounds for #{parts[0..index - 1].join(".")}"
            end

            current = current[index_val]
          else
            # Attribute name - check if method exists
            unless current.respond_to?(part)
              raise InvalidKeyError, "No method #{part} on #{current.class} at #{parts[0..index - 1].join(".")}"
            end

            current = current.public_send(part)
          end
        end
      end

      # Extract polymorphic updates that need special handling
      def extract_polymorphic_updates(attributes)
        polymorphic_updates = []

        attributes.each do |attr_update|
          key = attr_update[:key]
          value = attr_update[:value]

          # Check if this is a polymorphic model replacement
          polymorphic_updates << attr_update if value.is_a?(Object) && @registry.registered?(value.class)
        end

        polymorphic_updates
      end

      # Handle polymorphic model updates with type changes
      def handle_polymorphic_update(model, attr_name, new_polymorphic_model)
        # Validate that the new model is registered
        unless @registry.registered?(new_polymorphic_model.class)
          raise PolymorphicUpdateError,
                "Cannot update with unregistered model #{new_polymorphic_model.class}"
        end

        # Get the current model to check for key compatibility
        current_model = model.public_send(attr_name)
        if current_model && @registry.registered?(current_model.class)
          current_registration = @registry.registration_for(current_model.class)
          new_registration = @registry.registration_for(new_polymorphic_model.class)

          # Check if they use the same key field
          if current_registration.key_field != new_registration.key_field
            raise PolymorphicUpdateError,
                  "Key field mismatch: #{current_registration.key_field} vs #{new_registration.key_field}"
          end

          # Ensure the key values match
          current_key = current_registration.extract_key(current_model)
          new_key = new_registration.extract_key(new_polymorphic_model)

          if current_key != new_key
            raise PolymorphicUpdateError,
                  "Key value mismatch: #{current_key} vs #{new_key}"
          end
        end

        # Update the attribute
        model.public_send("#{attr_name}=", new_polymorphic_model)
      end

      # Try to upgrade a model to a polymorphic subclass that supports the attribute
      def try_polymorphic_upgrade(model, attr_name, value)
        # This is a simplified approach - in a real implementation, you might want
        # more sophisticated polymorphic type resolution
        return false unless @registry.registered?(model.class)

        registration = @registry.registration_for(model.class)

        # Look for registered subclasses that have the attribute
        @registry.registered_models.each do |registered_class|
          next unless registered_class > model.class # Must be a subclass
          next unless registered_class.instance_methods.include?("#{attr_name}=".to_sym)

          # Check if they use the same key field
          subclass_registration = @registry.registration_for(registered_class)
          next unless subclass_registration.key_field == registration.key_field

          # Try to upgrade the model
          begin
            # Get current model data
            current_data = if model.respond_to?(:to_hash)
                             model.to_hash
                           elsif model.respond_to?(:to_h)
                             model.to_h
                           else
                             {}
                           end

            # Add the new attribute
            current_data[attr_name.to_s] = value

            # Create new instance of the subclass
            upgraded_model = if registered_class.respond_to?(:from_h)
                               registered_class.from_h(current_data)
                             else
                               registered_class.new(current_data)
                             end

            # Copy the upgraded model's attributes back to the original model
            # This is a bit of a hack, but it allows the update to work
            upgraded_model.instance_variables.each do |var|
              model.instance_variable_set(var, upgraded_model.instance_variable_get(var))
            end

            # Change the model's class (this is Ruby metaprogramming magic)
            model.extend(registered_class)

            return true
          rescue StandardError
            # If upgrade fails, continue to next subclass
            next
          end
        end

        false
      end
    end
  end
end
