# frozen_string_literal: true

module Lutaml
  module Store
    # Store-centric API with model registry and database-style operations
    class DatabaseStore
      attr_reader :store, :registry, :composite_handler, :attribute_updater

      def initialize(adapter:, models: [], **options)
        @store = BasicStore.new(adapter_type: adapter, **options)
        @registry = ModelRegistry.new(models)
        @serializer = ModelSerializer.new
        @composite_handler = CompositeModelHandler.new(@registry, @store, self, serializer: @serializer)
        @attribute_updater = AttributeUpdater.new(@registry, @composite_handler)

        validate_configuration!
      end

      # Save single model or array of models
      def save(models)
        models_array = Array(models)
        saved_models = models_array.map { |model| save_single_model(model) }

        @store.emit_event(:model_save, models: saved_models, count: saved_models.size)
        models.is_a?(Array) ? saved_models : saved_models.first
      end

      # Fetch model by class and key field
      def fetch(model:, **key_params)
        registration = @registry.registration_for(model)
        key_field = registration.key_field
        key_value = key_params[key_field]
        raise InvalidKeyError, "Key field '#{key_field}' not provided" if key_value.nil?

        stored_data = find_stored_data(registration, model, key_value)
        return nil unless stored_data

        model_instance = @serializer.deserialize(stored_data, model, registration)

        composite_references = stored_data["_composite_models"]
        if composite_references
          model_instance = @composite_handler.restore_composite_models(
            model_instance, composite_references
          )
        end

        @store.emit_event(:model_fetch, model: model_instance, key: key_value, source: :backend)
        model_instance
      end

      # Update model with attributes array or block
      def update(model:, attributes: nil, **key_params, &block)
        current_model = fetch(model: model, **key_params)
        raise ModelNotRegisteredError, "Model not found" unless current_model

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

        save(updated_model)

        @store.emit_event(:model_update,
                          model: updated_model,
                          key: key_params,
                          changes: extract_changes(current_model, updated_model))

        updated_model
      end

      # Destroy model by class and key field
      def destroy(model:, **key_params)
        registration = @registry.registration_for(model)
        key_field = registration.key_field
        key_value = key_params[key_field]
        raise InvalidKeyError, "Key field '#{key_field}' not provided" if key_value.nil?

        model_instance = fetch(model: model, **key_params)
        return false unless model_instance

        @composite_handler.delete_composite_models(model_instance)

        storage_key = registration.generate_storage_key_from_value(key_value)
        deleted = @store.delete(storage_key)

        @store.emit_event(:model_destroy, model: model, key: key_value, deleted: deleted)
        deleted
      end

      # Query operations
      def where(model:, **conditions)
        all(model: model).select do |model_instance|
          conditions.all? { |field, value| model_instance.public_send(field) == value }
        end
      end

      # Get all models of a specific type
      def all(model:)
        registration = @registry.registration_for(model)

        models = []
        @store.each_key do |storage_key|
          parsed = StorageKey.parse(storage_key.to_s)
          next unless parsed.class_name == model.name

          stored_data = @store.get(storage_key)
          next unless stored_data

          begin
            model_instance = @serializer.deserialize(stored_data, model, registration)

            composite_references = stored_data["_composite_models"]
            if composite_references
              model_instance = @composite_handler.restore_composite_models(
                model_instance, composite_references
              )
            end

            models << model_instance
          rescue StandardError => e
            @store.emit_event(:deserialization_error, key: storage_key, error: e)
          end
        end

        models
      end

      def exists?(model:, **key_params)
        !fetch(model: model, **key_params).nil?
      end

      def count(model:)
        all(model: model).size
      end

      # Load all models of a type from a directory using format-specific serialization.
      # Bypasses the key-value layer and reads files directly using the format handler.
      def load_all(model_class, path: nil, format: :yaml, layout: :separate)
        fmt = Format.resolve(format)
        dir = resolve_model_dir(model_class, path)

        raise BackendError, "No directory specified for load_all" unless dir
        raise BackendError, "Directory not found: #{dir}" unless Dir.exist?(dir)

        case layout
        when :separate
          load_separate(dir, model_class, fmt)
        when :grouped
          load_grouped(dir, model_class, fmt)
        when :flat
          load_flat(dir, model_class, fmt)
        else
          raise ConfigurationError, "Unknown layout: #{layout}"
        end
      end

      # Load from directory and store into the key-value backend.
      # Returns the loaded models and makes them available via fetch/where/all.
      def import_all(model_class, path: nil, format: :yaml, layout: :separate)
        models = load_all(model_class, path: path, format: format, layout: layout)
        models.each { |model| save(model) }
        @store.emit_event(:model_import, count: models.size, path: path)
        models
      end

      # Save all models to a directory using format-specific serialization.
      def save_all(models, path: nil, format: :yaml, layout: :separate)
        fmt = Format.resolve(format)
        models_array = Array(models)
        return [] if models_array.empty?

        model_class = models_array.first.class
        dir = resolve_model_dir(model_class, path)

        raise BackendError, "No directory specified for save_all" unless dir

        FileUtils.mkdir_p(dir)

        saved = case layout
                when :separate
                  save_separate(models_array, dir, fmt)
                when :grouped
                  save_grouped(models_array, dir, fmt, model_class)
                when :flat
                  save_flat(models_array, dir, fmt)
                else
                  raise ConfigurationError, "Unknown layout: #{layout}"
                end

        @store.emit_event(:model_save_all, models: saved, count: saved.size, path: dir)
        saved
      end

      # Export models to a single file or directory.
      def export(models, path:, format: :yaml)
        fmt = Format.resolve(format)
        models_array = Array(models)

        FileUtils.mkdir_p(File.dirname(path))

        content = fmt.serialize_many(models_array)

        File.write(path, content, encoding: "utf-8")
        @store.emit_event(:model_export, count: models_array.size, path: path)
        path
      end

      def on(event, &block)
        @store.on(event, &block)
      end

      def off(event, listener)
        @store.off(event, listener)
      end

      def stats
        base_stats = @store.stats
        base_stats.merge(
          models_registered: @registry.count,
          registered_models: @registry.registered_models.map(&:name),
          total_models: total_model_count
        )
      end

      def close
        @store.close
      end

      private

      def find_stored_data(registration, model, key_value)
        if registration.polymorphic?
          find_polymorphic_data(model, key_value)
        else
          storage_key = registration.generate_storage_key_from_value(key_value)
          @store.get(storage_key)
        end
      end

      def find_polymorphic_data(model, key_value)
        candidates = @store.keys
                           .filter_map do |key|
                             parsed = StorageKey.parse(key.to_s)
                             next unless parsed.key_value == key_value.to_s

                             data = @store.get(key)
                             next unless data&.key?("_class")

                             stored_class = Object.const_get(data["_class"])
                             next unless stored_class <= model

                             { key: key, data: data, klass: stored_class }
                           end

        candidates.max_by { |c| polymorphic_depth(c[:klass], model) }&.dig(:data)
      end

      def polymorphic_depth(klass, base)
        depth = 0
        current = klass
        while current < base && current.superclass
          current = current.superclass
          depth += 1
        end
        depth
      end

      def save_single_model(model)
        registration = @registry.registration_for(model.class)
        composite_references = @composite_handler.process_composite_models(model)
        serialized_data = @serializer.serialize(model, registration)

        serialized_data["_composite_models"] = composite_references unless composite_references.empty?

        storage_key = registration.generate_storage_key(model)
        @store.set(storage_key, serialized_data)

        unless composite_references.empty?
          @store.emit_event(:composite_model_stored,
                            model: model,
                            composite_count: composite_references.size)
        end

        model
      end

      def extract_changes(old_model, new_model)
        registration = @registry.registration_for(old_model.class)
        old_attrs = @serializer.serialize(old_model, registration)
        new_attrs = @serializer.serialize(new_model, registration)

        new_attrs.each_with_object({}) do |(key, new_value), changes|
          old_value = old_attrs[key]
          changes[key] = { from: old_value, to: new_value } if old_value != new_value
        end
      end

      def total_model_count
        @registry.registered_models.sum { |model_class| count(model: model_class) }
      end

      def validate_configuration!
        return unless @registry.empty?

        raise ConfigurationError,
              "No models registered. Provide models: [{ model: YourModel, key: :key_field }]"
      end

      # ── Layout helpers ──

      def resolve_model_dir(model_class, base_path)
        registration = @registry.find_registration(model_class)
        return base_path unless registration

        dir = registration.dir
        return base_path unless dir

        base_path ? File.join(base_path, dir) : nil
      end

      def load_separate(dir, model_class, fmt)
        models = []
        glob = File.join(dir, fmt.glob_pattern)
        Dir.glob(glob).sort.each do |file_path|
          next unless File.file?(file_path)

          raw = File.read(file_path, encoding: "utf-8")
          next if raw.strip.empty?

          begin
            model = fmt.deserialize(raw, model_class)
            set_model_key_from_filename(model, file_path, fmt)
            models << model
          rescue StandardError => e
            @store.emit_event(:load_error, file: file_path, error: e)
          end
        end
        models
      end

      def load_grouped(dir, model_class, fmt)
        models = []
        glob = File.join(dir, fmt.glob_pattern)
        Dir.glob(glob).sort.each do |file_path|
          next unless File.file?(file_path)

          raw = File.read(file_path, encoding: "utf-8")
          next if raw.strip.empty?

          begin
            loaded = fmt.deserialize_many(raw, model_class)
            loaded = [loaded] unless loaded.is_a?(Array)
            loaded.each { |m| set_model_key_from_filename(m, file_path, fmt) }
            models.concat(loaded)
          rescue StandardError => e
            @store.emit_event(:load_error, file: file_path, error: e)
          end
        end
        models
      end

      def load_flat(dir, model_class, fmt)
        load_separate(dir, model_class, fmt)
      end

      def save_separate(models, dir, fmt)
        models.map do |model|
          key = extract_model_key(model)
          filename = key || model.class.name.to_s.gsub("::", "_")
          file_path = File.join(dir, "#{filename}#{fmt.extension}")
          content = fmt.serialize(model)
          File.write(file_path, content, encoding: "utf-8")
          model
        end
      end

      def save_grouped(models, dir, fmt, _model_class)
        grouped = {}
        models.each do |model|
          key = extract_model_key(model) || model.class.name.to_s.gsub("::", "_")
          grouped[key] ||= []
          grouped[key] << model
        end

        grouped.map do |key, group|
          file_path = File.join(dir, "#{key}#{fmt.extension}")
          content = fmt.serialize_many(group)
          File.write(file_path, content, encoding: "utf-8")
          group
        end.flatten
      end

      def save_flat(models, dir, fmt)
        save_separate(models, dir, fmt)
      end

      def extract_model_key(model)
        registration = @registry.find_registration(model.class)
        return nil unless registration

        key_value = model.public_send(registration.key_field)
        key_value&.to_s
      rescue StandardError
        nil
      end

      def set_model_key_from_filename(model, file_path, _fmt)
        return if extract_model_key(model)

        registration = @registry.find_registration(model.class)
        return unless registration

        basename = File.basename(file_path, ".*")
        model.public_send(:"#{registration.key_field}=", basename)
      end
    end
  end
end
