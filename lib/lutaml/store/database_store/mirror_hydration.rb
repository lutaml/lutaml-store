# frozen_string_literal: true

module Lutaml
  module Store
    class DatabaseStore
      # Mirror-hydrated records: registration at load and model-aware
      # sorting over the mixed record union (stored hashes + live models).
      module MirrorHydration
        # Register a model the transport just parsed from its authoritative
        # source. The live model answers reads directly (no serialization,
        # no backend write); a later save over its key hands the key back
        # to the backend.
        def register_loaded_model(model)
          registration = @registry.registration_for(model.class)
          storage_key = registration.generate_storage_key(model)
          @store.adapter.register_mirror(
            MirrorRef.new(storage_key: storage_key,
                          model_class_name: model.class.name,
                          reader: -> { model })
          )
          model
        end

        # Stored records are hashes; mirror-hydrated records are live models.
        def sort_field_value(record, field)
          return record[field.to_s] if record.is_a?(Hash)
          return unless record.is_a?(Lutaml::Model::Serializable)

          record.public_send(field)
        end
      end
    end
  end
end
