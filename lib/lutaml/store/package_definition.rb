# frozen_string_literal: true

module Lutaml
  module Store
    class PackageDefinition
      attr_reader :name, :model_entries, :asset_entries,
                  :metadata_model, :metadata_file, :metadata_key

      def initialize(name:, metadata_model: nil, metadata_file: nil,
                     metadata_key: :shortname)
        @name = name
        @metadata_model = metadata_model
        @metadata_file = metadata_file
        @metadata_key = metadata_key
        @model_entries = []
        @asset_entries = []
        yield self if block_given?
      end

      def model(model:, key:, dir: nil, file: nil, layout: :separate,
                default_format: :yaml, serializer: nil)
        raise ArgumentError, "Specify dir: or file:, not both" if dir && file

        @model_entries << ModelEntry.new(
          model: model, dir: dir, file: file, layout: layout,
          key: key, default_format: default_format, serializer: serializer
        )
      end

      def asset(path, type: :file)
        @asset_entries << AssetEntry.new(path: path, type: type)
      end

      def entry_for(model_class)
        @model_entries.find { |e| e.model == model_class }
      end

      def model_classes
        @model_entries.map(&:model)
      end

      def database_store_models
        @model_entries.map do |e|
          config = { model: e.model, key: e.key }
          config[:serializer] = e.serializer if e.serializer
          config[:dir] = e.dir if e.dir
          config
        end
      end

      ModelEntry = Struct.new(
        :model, :dir, :file, :layout, :key, :default_format, :serializer,
        keyword_init: true
      )

      AssetEntry = Struct.new(
        :path, :type,
        keyword_init: true
      )
    end
  end
end
