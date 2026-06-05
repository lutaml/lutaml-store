# frozen_string_literal: true

require "zip"

module Lutaml
  module Store
    module PackageTransport
      class ZipTransport < Base
        def read(path, package_store, format: nil)
          definition = package_store.definition
          global_format = format

          Zip::File.open(path) do |zip_file|
            read_metadata_zip(zip_file, package_store)

            definition.model_entries.each do |entry|
              fmt_name = global_format || entry.default_format
              read_model_entry_zip(zip_file, entry, package_store, fmt_name)
            end

            definition.asset_entries.each do |entry|
              read_asset_entry_zip(zip_file, entry, package_store)
            end
          end
        end

        def write(path, package_store, formats: {})
          definition = package_store.definition
          FileUtils.mkdir_p(File.dirname(path))

          Zip::File.open(path, create: true) do |zip_file|
            write_metadata_zip(zip_file, package_store)

            definition.model_entries.each do |entry|
              fmt_name = effective_format(entry, formats)
              fmt = resolve_format(fmt_name)
              write_model_entry_zip(zip_file, entry, package_store, fmt)
            end

            write_assets_zip(zip_file, package_store)
          end
        end

        private

        def read_metadata_zip(zip_file, package_store)
          definition = package_store.definition
          return unless definition.metadata_model && definition.metadata_file

          entry = zip_file.find_entry(definition.metadata_file)
          return unless entry

          fmt = format_for_file(definition.metadata_file)
          raw = entry.get_input_stream.read
          metadata = fmt.deserialize(raw, definition.metadata_model)
          package_store.metadata = metadata
        end

        def write_metadata_zip(zip_file, package_store)
          return unless package_store.metadata

          definition = package_store.definition
          fmt = format_for_file(definition.metadata_file)
          content = fmt.serialize(package_store.metadata)
          zip_file.get_output_stream(definition.metadata_file) { |f| f.write(content) }
        end

        def read_model_entry_zip(zip_file, entry, package_store, fmt_name)
          fmt = resolve_format(fmt_name)

          if entry.file
            read_single_file_zip(zip_file, entry, package_store, fmt)
          else
            read_directory_zip(zip_file, entry, package_store, fmt)
          end
        end

        def read_single_file_zip(zip_file, entry, package_store, fmt)
          zip_entry = zip_file.find_entry(entry.file)
          return unless zip_entry

          raw = zip_entry.get_input_stream.read
          model = fmt.deserialize(raw, entry.model)
          package_store.add_model(model)
        end

        def read_directory_zip(zip_file, entry, package_store, fmt)
          prefix = entry.dir ? "#{entry.dir}/" : ""

          zip_file.entries.each do |zip_entry|
            next unless zip_entry.name.start_with?(prefix)
            next unless matches_format?(zip_entry.name, fmt)
            next if zip_entry.name == prefix || zip_entry.name.end_with?("/")

            raw = zip_entry.get_input_stream.read
            next if raw.strip.empty?

            begin
              loaded = fmt.deserialize_many(raw, entry.model)
              loaded = [loaded] unless loaded.is_a?(Array)
              loaded.each do |m|
                set_key_from_zip_path(m, zip_entry.name, entry, prefix)
                package_store.add_model(m)
              end
            rescue StandardError => e
              warn "PackageStore: failed to load #{zip_entry.name}: #{e.message}"
            end
          end
        end

        def write_model_entry_zip(zip_file, entry, package_store, fmt)
          models = package_store.models_for(entry.model)
          return if models.empty?

          if entry.file
            content = entry.layout == :grouped ? fmt.serialize_many(models) : fmt.serialize(models.first)
            zip_file.get_output_stream(entry.file) { |f| f.write(content) }
          else
            write_directory_models_zip(zip_file, entry, models, fmt)
          end
        end

        def write_directory_models_zip(zip_file, entry, models, fmt)
          prefix = entry.dir ? "#{entry.dir}/" : ""

          case entry.layout
          when :grouped
            models.group_by { |m| extract_key(m, entry) }.each do |key, group|
              filename = "#{prefix}#{sanitize_filename(key)}#{fmt.extension}"
              zip_file.get_output_stream(filename) { |f| f.write(fmt.serialize_many(group)) }
            end
          else
            models.each do |model|
              key = extract_key(model, entry)
              filename = "#{prefix}#{sanitize_filename(key)}#{fmt.extension}"
              zip_file.get_output_stream(filename) { |f| f.write(fmt.serialize(model)) }
            end
          end
        end

        def read_asset_entry_zip(zip_file, entry, package_store)
          case entry.type
          when :file
            zip_entry = zip_file.find_entry(entry.path)
            package_store.add_asset(entry.path, zip_entry.get_input_stream.read) if zip_entry
          when :directory
            prefix = entry.path.end_with?("/") ? entry.path : "#{entry.path}/"
            zip_file.entries.each do |zip_entry|
              next unless zip_entry.name.start_with?(prefix)
              next if zip_entry.name == prefix || zip_entry.name.end_with?("/")

              package_store.add_asset(zip_entry.name, zip_entry.get_input_stream.read)
            end
          end
        end

        def write_assets_zip(zip_file, package_store)
          package_store.asset_paths.each do |asset_path|
            content = package_store.asset(asset_path)
            zip_file.get_output_stream(asset_path) { |f| f.write(content) } if content
          end
        end

        def set_key_from_zip_path(model, zip_path, entry, prefix)
          return if model.public_send(entry.key)

          filename = zip_path.sub(prefix, "")
          set_key_from_filename(model, filename, entry)
        end

        def matches_format?(name, fmt)
          ext = File.extname(name)
          ext == fmt.extension || (fmt.extension == ".yaml" && ext == ".yml")
        end
      end
    end
  end
end
