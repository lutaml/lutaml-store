# frozen_string_literal: true

module Lutaml
  module Store
    # Manages registered models with their key fields and polymorphic configurations
    class ModelRegistry
      def initialize(model_configs = [])
        @registrations = {}
        register_models(model_configs)
      end

      # Register a single model
      def register(model_class, key_field, **options)
        registration = ModelRegistration.new(model_class, key_field, **options)
        @registrations[model_class] = registration
        registration
      end

      # Register multiple models from configuration array
      def register_models(model_configs)
        model_configs.each do |config|
          raise ConfigurationError, "Invalid model configuration: #{config}" unless config.is_a?(Hash)

          model_class = config[:model]
          key_field = config[:key]
          register(model_class, key_field, **config.except(:model, :key))
        end
      end

      # Find registration for model class or its superclass
      def find_registration(model_class)
        # First try exact match
        return @registrations[model_class] if @registrations[model_class]

        # Then try inheritance chain
        @registrations.each_value do |registration|
          return registration if registration.matches_model?(model_class)
        end

        nil
      end

      # Check if model is registered
      def registered?(model_class)
        !find_registration(model_class).nil?
      end

      # Get registration for model class (raises error if not found)
      def registration_for(model_class)
        registration = find_registration(model_class)
        unless registration
          raise ModelNotRegisteredError,
                "Model #{model_class} is not registered. " \
                "Register it with: models: [{ model: #{model_class}, key: :key_field }]"
        end
        registration
      end

      # Get all registered model classes
      def registered_models
        @registrations.keys
      end

      # Get all registrations
      def registrations
        @registrations.values
      end

      # Check if any models are registered
      def empty?
        @registrations.empty?
      end

      # Get count of registered models
      def count
        @registrations.size
      end

      # Clear all registrations
      def clear
        @registrations.clear
      end

      # Find models that are registered and nested within other models
      def find_composite_models(model)
        composite_models = {}

        model.class.attributes.each_key do |attr_name|
          attr_value = model.public_send(attr_name)
          next if attr_value.nil?

          add_composite_entry(composite_models, attr_name, attr_value) if attr_value.is_a?(Object) && registered?(attr_value.class)

          next unless attr_value.is_a?(Array)

          attr_value.each_with_index do |item, index|
            next unless item.is_a?(Object) && registered?(item.class)

            add_composite_entry(composite_models, "#{attr_name}.#{index}", item)
          end
        end

        composite_models
      rescue NoMethodError
        {}
      end

      private

      def add_composite_entry(composite_models, attr_path, model_instance)
        registration = find_registration(model_instance.class)
        key_value = model_instance.public_send(registration.key_field)
        return if key_value.nil?

        composite_models[attr_path] = {
          model: model_instance,
          registration: registration,
          key_value: key_value.to_s
        }
      end
    end
  end
end
