# frozen_string_literal: true

module Lutaml
  module Store
    class PackageStore
      attr_accessor :metadata
      attr_reader :definition, :assets

      def initialize(definition)
        @definition = definition
        @db = DatabaseStore.new(
          adapter: :memory,
          models: definition.database_store_models
        )
        @assets = {}
        @metadata = nil
      end

      # ── Load / Save ──

      def self.load(definition, path, transport: :directory, format: nil)
        store = new(definition)
        transporter = resolve_transport(transport)
        transporter.read(path, store, format: format)
        store
      end

      def save(path, transport: :directory, format: nil, formats: {})
        resolved_formats = resolve_formats(format, formats)
        transporter = self.class.resolve_transport(transport)
        transporter.write(path, self, formats: resolved_formats)
      end

      # ── Model CRUD ──

      def add_model(model_instance)
        @db.save(model_instance)
      end

      def add_models(model_instances)
        model_instances.each { |m| add_model(m) }
      end

      def fetch_model(model_class, key)
        entry = definition.entry_for(model_class)
        @db.fetch(model: model_class, **{ entry.key => key })
      end

      def models_for(model_class)
        @db.all(model: model_class)
      end

      def model_count(model_class)
        @db.count(model: model_class)
      end

      def model_exists?(model_class, key)
        entry = definition.entry_for(model_class)
        @db.exists?(model: model_class, **{ entry.key => key })
      end

      def remove_model(model_class, key)
        entry = definition.entry_for(model_class)
        @db.destroy(model: model_class, **{ entry.key => key })
      end

      # ── Metadata ──

      # ── Assets ──

      def asset(path)
        @assets[path]
      end

      def add_asset(path, content)
        @assets[path] = content
      end

      def asset_paths
        @assets.keys
      end

      def remove_asset(path)
        @assets.delete(path)
      end

      # ── Bulk ──

      def clear_models(model_class)
        @db.all(model: model_class).each do |m|
          entry = definition.entry_for(model_class)
          key = m.public_send(entry.key)
          @db.destroy(model: model_class, **{ entry.key => key })
        end
      end

      def clear_assets
        @assets.clear
      end

      def clear_all
        definition.model_classes.each { |mc| clear_models(mc) }
        clear_assets
        @metadata = nil
      end

      # ── Stats ──

      def stats
        model_stats = definition.model_classes
                                .map { |mc| [mc.name, model_count(mc)] }
                                .to_h
        {
          package: definition.name,
          models: model_stats,
          assets: @assets.size,
          metadata: @metadata ? true : false
        }
      end

      # Public access for PackageTransport (avoids instance_variable_get).
      attr_reader :db

      private

      def self.resolve_transport(transport)
        case transport
        when :directory, "directory"
          PackageTransport::DirectoryTransport.new
        when :zip, "zip"
          PackageTransport::ZipTransport.new
        else
          raise ConfigurationError, "Unknown transport: #{transport}"
        end
      end

      def resolve_formats(global_format, per_model_formats)
        if global_format
          definition.model_entries
                    .map { |e| [e.model, global_format] }
                    .to_h
                    .merge(per_model_formats)
        else
          per_model_formats
        end
      end
    end
  end
end
