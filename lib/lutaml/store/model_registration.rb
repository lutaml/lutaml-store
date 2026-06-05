# frozen_string_literal: true

module Lutaml
  module Store
    # Represents a single model registration with its metadata
    class ModelRegistration
      attr_reader :model_class, :key_field, :polymorphic_class_key, :serializer, :dir,
                  :composites

      def initialize(model_class, key_field, polymorphic_class_key: nil, serializer: nil,
                     dir: nil, composites: [])
        @model_class = model_class
        @key_field = key_field.to_sym
        @polymorphic_class_key = polymorphic_class_key&.to_sym
        @serializer = serializer
        @dir = dir
        @composites = composites.map(&:to_sym)
        validate!
      end

      # Extract key value from model instance
      def extract_key(model)
        key_value = model.public_send(@key_field)
        raise InvalidKeyError, "Key field '#{@key_field}' is nil for #{@model_class}" if key_value.nil?

        key_value.to_s
      end

      # Check if registration supports polymorphism
      def polymorphic?
        !@polymorphic_class_key.nil?
      end

      # Extract polymorphic class from model instance
      def extract_polymorphic_class(model)
        return @model_class.name unless polymorphic?

        polymorphic_value = model.public_send(@polymorphic_class_key)
        polymorphic_value || @model_class.name
      end

      # Generate storage key for model
      def generate_storage_key(model)
        StorageKey.new(model.class.name, extract_key(model))
      end

      # Generate storage key from key value and optional polymorphic class
      def generate_storage_key_from_value(key_value, polymorphic_class = nil)
        class_name = polymorphic_class || @model_class.name
        StorageKey.new(class_name, key_value)
      end

      # Check if model class matches this registration (including inheritance)
      def matches_model?(model_class)
        model_class <= @model_class
      end

      private

      def validate!
        # Check if key field exists on model
        unless @model_class.method_defined?(@key_field) ||
               @model_class.private_method_defined?(@key_field)
          raise ConfigurationError,
                "Key field '#{@key_field}' does not exist on #{@model_class}"
        end

        # Check if polymorphic class key exists when specified
        if polymorphic? &&
           !@model_class.method_defined?(@polymorphic_class_key) &&
           !@model_class.private_method_defined?(@polymorphic_class_key)
          raise ConfigurationError,
                "Polymorphic class key '#{@polymorphic_class_key}' does not exist on #{@model_class}"
        end
      end
    end
  end
end
