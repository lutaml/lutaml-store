# frozen_string_literal: true

require_relative "store"
require_relative "serializer"
require_relative "compression"

module Lutaml
  module Store
    class ModelStore
      attr_reader :store, :format, :model_class

      def initialize(config = {}, model_class: nil, format: :marshal)
        @store = Store.new(config)
        @model_class = model_class
        @format = format
        validate_format!
      end

      def self.from_file(config_file, model_class: nil, format: :marshal)
        new(Store.load_config(config_file), model_class: model_class, format: format)
      end

      # Store a Lutaml::Model instance
      def store_model(key, model)
        validate_model!(model) if @model_class
        validate_model_data!(model) if @store.config.validate_on_write?

        serialized = Serializer.serialize(model, @format)

        # Apply compression if enabled
        if @store.config.compression_enabled?
          serialized = Compression.compress(
            serialized,
            @store.config.compression_algorithm,
            @store.config.compression_level
          )
        end

        @store.set(key, serialized)
        emit_event(:store_model, key: key, model: model, format: @format)
        model
      end

      # Retrieve a Lutaml::Model instance
      def get_model(key)
        serialized = @store.get(key)
        return nil unless serialized

        # Decompress if compression is enabled or auto-detect compression
        if @store.config.compression_enabled?
          serialized = Compression.decompress(serialized, @store.config.compression_algorithm)
        elsif (detected_algorithm = Compression.detect_algorithm(serialized))
          serialized = Compression.decompress(serialized, detected_algorithm)
        end

        model = Serializer.deserialize(serialized, @format, @model_class)
        emit_event(:get_model, key: key, model: model, format: @format, source: :backend)
        model
      end

      # Store multiple models with a key generator
      def store_models(models, key_generator = nil)
        key_generator ||= ->(model, index) { "#{model.class.name.downcase}_#{index}" }

        models.each_with_index do |model, index|
          key = key_generator.call(model, index)
          store_model(key, model)
        end
      end

      # Get all models of the configured type
      def all_models
        all_data = @store.all
        models = {}

        all_data.each do |key, serialized|
          begin
            # Decompress if compression is enabled or auto-detect compression
            if @store.config.compression_enabled?
              serialized = Compression.decompress(serialized, @store.config.compression_algorithm)
            elsif (detected_algorithm = Compression.detect_algorithm(serialized))
              serialized = Compression.decompress(serialized, detected_algorithm)
            end

            model = Serializer.deserialize(serialized, @format, @model_class)
            models[key] = model
          rescue => e
            # Skip invalid entries
            emit_event(:deserialization_error, key: key, error: e)
          end
        end

        models
      end

      # Find models by criteria (block-based)
      def find_models(&block)
        return enum_for(:find_models) unless block_given?

        all_models.select { |key, model| block.call(key, model) }
      end

      # Update a model
      def update_model(key, &block)
        model = get_model(key)
        return nil unless model

        updated_model = block.call(model)
        store_model(key, updated_model)
        updated_model
      end

      # Delete a model
      def delete_model(key)
        deleted = @store.delete(key)
        emit_event(:delete_model, key: key, deleted: deleted) if deleted
        deleted
      end

      # Check if a model exists
      def model_exists?(key)
        @store.exists?(key)
      end

      # Get model keys
      def model_keys
        @store.keys
      end

      # Count models
      def model_count
        @store.size
      end

      # Clear all models
      def clear_models
        @store.clear
        emit_event(:clear_models)
      end

      # Bulk operations
      def bulk_store(key_model_pairs)
        key_model_pairs.each do |key, model|
          store_model(key, model)
        end
      end

      def bulk_get(keys)
        keys.map { |key| [key, get_model(key)] }.to_h
      end

      def bulk_delete(keys)
        keys.map { |key| [key, delete_model(key)] }.to_h
      end

      # Export models to different format
      def export_models(target_format)
        return enum_for(:export_models, target_format) unless block_given?

        all_models.each do |key, model|
          exported = Serializer.serialize(model, target_format)
          yield key, exported
        end
      end

      # Import models from different format
      def import_models(data, source_format, key_generator = nil)
        key_generator ||= ->(key, _) { key }

        data.each do |key, serialized|
          begin
            model = Serializer.deserialize(serialized, source_format, @model_class)
            new_key = key_generator.call(key, model)
            store_model(new_key, model)
          rescue => e
            emit_event(:import_error, key: key, error: e)
          end
        end
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
          model_class: @model_class&.name,
          format: @format,
          model_count: model_count
        })
      end

      def cache_stats
        @store.cache_stats
      end

      # Resource management
      def close
        @store.close
      end

      private

      def validate_format!
        unless Serializer::SUPPORTED_FORMATS.include?(@format)
          raise ConfigurationError, "Unsupported format: #{@format}. Supported: #{Serializer::SUPPORTED_FORMATS.join(', ')}"
        end
      end

      def validate_model!(model)
        unless model.is_a?(@model_class)
          raise ArgumentError, "Expected #{@model_class}, got #{model.class}"
        end
      end

      def validate_model_data!(model)
        if model.respond_to?(:validate)
          model.validate
        end
      end

      def emit_event(event, data = {})
        @store.instance_variable_get(:@events)&.emit(event, data)
      end
    end
  end
end
