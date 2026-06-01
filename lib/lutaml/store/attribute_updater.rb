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

        @composite_handler.update_composite_models(updated_model, attributes)

        updated_model
      end

      # Update model with block
      def update_with_block(model, &block)
        return model unless block_given?

        updated_model = model.dup
        block.call(updated_model)

        composite_models = @registry.find_composite_models(updated_model)
        @composite_handler.process_composite_models(updated_model) unless composite_models.empty?

        updated_model
      end

      # Update model with hash
      def update_with_hash(model, updates_hash)
        return model if updates_hash.nil? || updates_hash.empty?

        attributes = updates_hash.map { |key, value| { key: key, value: value } }
        update_with_attributes(model, attributes)
      end

      private

      def update_nested_attribute(model, attr_path, value)
        parts = attr_path.split(".")
        current = model

        parts[0..-2].each do |part|
          current = if part.match?(/\A\d+\z/)
                      current[part.to_i]
                    else
                      current.public_send(part)
                    end

          raise InvalidKeyError, "Cannot navigate to #{attr_path}: #{part} is nil" if current.nil?
        end

        final_attr = parts.last
        if final_attr.match?(/\A\d+\z/)
          current[final_attr.to_i] = value
        else
          setter_method = "#{final_attr}="
          begin
            current.public_send(setter_method, value)
          rescue NoMethodError
            raise InvalidKeyError, "No setter method #{setter_method} on #{current.class}"
          end
        end
      end

      def update_direct_attribute(model, attr_name, value)
        setter_method = "#{attr_name}="

        begin
          model.public_send(setter_method, value)
        rescue NoMethodError
          return if try_polymorphic_upgrade(model, attr_name, value)

          raise InvalidKeyError, "No setter method #{setter_method} on #{model.class}"
        end
      end

      # Validate attribute path without respond_to? on leaf — use is_a? for type checking
      def validate_attribute_path(model, attr_path)
        parts = attr_path.split(".")
        current = model

        parts.each_with_index do |part, index|
          if part.match?(/\A\d+\z/)
            raise InvalidKeyError, "Expected array at #{parts[0..index - 1].join(".")}, got #{current.class}" unless current.is_a?(Array)

            index_val = part.to_i
            raise InvalidKeyError, "Array index #{index_val} out of bounds for #{parts[0..index - 1].join(".")}" if index_val >= current.length

            current = current[index_val]
          else
            unless current.is_a?(Lutaml::Model::Serializable) || current.public_methods.include?(part.to_sym)
              raise InvalidKeyError, "No method #{part} on #{current.class} at #{parts[0..index - 1].join(".")}"
            end

            current = current.public_send(part)
          end
        end
      end

      def extract_polymorphic_updates(attributes)
        attributes.select do |attr_update|
          value = attr_update[:value]
          value.is_a?(Object) && @registry.registered?(value.class)
        end
      end

      def handle_polymorphic_update(model, attr_name, new_polymorphic_model)
        unless @registry.registered?(new_polymorphic_model.class)
          raise PolymorphicUpdateError,
                "Cannot update with unregistered model #{new_polymorphic_model.class}"
        end

        current_model = model.public_send(attr_name)
        validate_polymorphic_key_compatibility!(current_model, new_polymorphic_model) if current_model && @registry.registered?(current_model.class)

        model.public_send("#{attr_name}=", new_polymorphic_model)
      end

      # Try to upgrade a model to a polymorphic subclass that supports the attribute.
      # Uses proper constructors instead of instance_variable_set/get.
      def try_polymorphic_upgrade(model, attr_name, value)
        return false unless @registry.registered?(model.class)

        registration = @registry.registration_for(model.class)

        @registry.registered_models.each do |registered_class|
          next unless registered_class > model.class
          next unless registered_class.instance_methods.include?("#{attr_name}=".to_sym)

          subclass_registration = @registry.registration_for(registered_class)
          next unless subclass_registration.key_field == registration.key_field

          begin
            current_data = model.to_hash
            current_data[attr_name.to_s] = value

            upgraded_model = registered_class.from_hash(current_data)
            copy_model_attributes!(model, upgraded_model)
            return true
          rescue StandardError
            next
          end
        end

        false
      end

      # Copy all Lutaml::Model attributes from source to target using public setters
      def copy_model_attributes!(target, source)
        source.class.attributes.each_key do |attr_name|
          setter = "#{attr_name}="
          begin
            target.public_send(setter, source.public_send(attr_name))
          rescue NoMethodError
            next
          end
        end
      end

      def validate_polymorphic_key_compatibility!(current_model, new_model)
        current_registration = @registry.registration_for(current_model.class)
        new_registration = @registry.registration_for(new_model.class)

        if current_registration.key_field != new_registration.key_field
          raise PolymorphicUpdateError,
                "Key field mismatch: #{current_registration.key_field} vs #{new_registration.key_field}"
        end

        current_key = current_registration.extract_key(current_model)
        new_key = new_registration.extract_key(new_model)

        return unless current_key != new_key

        raise PolymorphicUpdateError,
              "Key value mismatch: #{current_key} vs #{new_key}"
      end
    end
  end
end
