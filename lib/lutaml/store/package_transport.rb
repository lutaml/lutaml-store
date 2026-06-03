# frozen_string_literal: true

require "zip"
require "fileutils"

module Lutaml
  module Store
    module PackageTransport
      class Base
        def read(path, package_store, format: nil)
          raise NotImplementedError
        end

        def write(path, package_store, formats: {})
          raise NotImplementedError
        end

        private

        def resolve_format(format_name)
          Format.resolve(format_name)
        end

        def effective_format(entry, formats)
          formats[entry.model] || entry.default_format
        end

        def format_for_file(filename)
          ext = File.extname(filename)
          case ext
          when ".yaml", ".yml" then Format.resolve(:yaml)
          when ".json" then Format.resolve(:json)
          else Format.resolve(:yaml)
          end
        end
      end

      class DirectoryTransport < Base
        def read(path, package_store, format: nil)
          definition = package_store.definition
          global_format = format

          read_metadata(path, package_store)

          definition.model_entries.each do |entry|
            fmt_name = global_format || entry.default_format
            read_model_entry(path, entry, package_store, fmt_name)
          end

          definition.asset_entries.each do |entry|
            read_asset_entry(path, entry, package_store)
          end
        end

        def write(path, package_store, formats: {})
          definition = package_store.definition
          FileUtils.mkdir_p(path)

          write_metadata(path, package_store)

          definition.model_entries.each do |entry|
            fmt_name = effective_format(entry, formats)
            fmt = resolve_format(fmt_name)
            write_model_entry(path, entry, package_store, fmt)
          end

          definition.asset_entries.each do |entry|
            write_asset_entry(path, entry, package_store)
          end
        end

        private

        # ── Metadata ──

        def read_metadata(path, package_store)
          definition = package_store.definition
          return unless definition.metadata_model && definition.metadata_file

          file_path = File.join(path, definition.metadata_file)
          return unless File.exist?(file_path)

          fmt = format_for_file(definition.metadata_file)
          raw = File.read(file_path, encoding: "utf-8")
          metadata = fmt.deserialize(raw, definition.metadata_model)
          package_store.metadata = metadata
        end

        def write_metadata(path, package_store)
          return unless package_store.metadata

          definition = package_store.definition
          fmt = format_for_file(definition.metadata_file)
          content = fmt.serialize(package_store.metadata)
          file_path = File.join(path, definition.metadata_file)
          FileUtils.mkdir_p(File.dirname(file_path))
          File.write(file_path, content, encoding: "utf-8")
        end

        # ── Model entries ──

        def read_model_entry(base_path, entry, package_store, fmt_name)
          if entry.file
            read_single_file_model(base_path, entry, package_store, fmt_name)
          else
            read_directory_models(base_path, entry, package_store, fmt_name)
          end
        end

        def read_single_file_model(base_path, entry, package_store, fmt_name)
          file_path = File.join(base_path, entry.file)
          return unless File.exist?(file_path)

          fmt = resolve_format(fmt_name)
          raw = File.read(file_path, encoding: "utf-8")
          model = fmt.deserialize(raw, entry.model)
          package_store.add_model(model)
        end

        def read_directory_models(base_path, entry, package_store, fmt_name)
          dir = entry.dir ? File.join(base_path, entry.dir) : base_path
          return unless Dir.exist?(dir)

          fmt = resolve_format(fmt_name)
          glob = File.join(dir, fmt.glob_pattern)

          Dir.glob(glob).sort.each do |file_path|
            next unless File.file?(file_path)

            raw = File.read(file_path, encoding: "utf-8")
            next if raw.strip.empty?

            begin
              case entry.layout
              when :grouped
                loaded = fmt.deserialize_many(raw, entry.model)
                loaded.each do |m|
                  set_key_from_filename(m, file_path, entry)
                  package_store.add_model(m)
                end
              else
                model = fmt.deserialize(raw, entry.model)
                set_key_from_filename(model, file_path, entry)
                package_store.add_model(model)
              end
            rescue StandardError => e
              warn "PackageStore: failed to load #{file_path}: #{e.message}"
            end
          end
        end

        def write_model_entry(base_path, entry, package_store, fmt)
          models = package_store.models_for(entry.model)
          return if models.empty?

          if entry.file
            write_single_file_model(base_path, entry, models, fmt)
          else
            write_directory_models(base_path, entry, models, fmt)
          end
        end

        def write_single_file_model(base_path, entry, models, fmt)
          content = case entry.layout
                    when :grouped
                      fmt.serialize_many(models)
                    else
                      fmt.serialize(models.first)
                    end
          file_path = File.join(base_path, entry.file)
          FileUtils.mkdir_p(File.dirname(file_path))
          File.write(file_path, content, encoding: "utf-8")
        end

        def write_directory_models(base_path, entry, models, fmt)
          dir = entry.dir ? File.join(base_path, entry.dir) : base_path
          FileUtils.mkdir_p(dir)

          case entry.layout
          when :grouped
            grouped = models.group_by { |m| extract_key(m, entry) }
            grouped.each do |key, group|
              file_path = File.join(dir, "#{sanitize_filename(key)}#{fmt.extension}")
              content = fmt.serialize_many(group)
              File.write(file_path, content, encoding: "utf-8")
            end
          else
            models.each do |model|
              key = extract_key(model, entry)
              file_path = File.join(dir, "#{sanitize_filename(key)}#{fmt.extension}")
              content = fmt.serialize(model)
              File.write(file_path, content, encoding: "utf-8")
            end
          end
        end

        # ── Assets ──

        def read_asset_entry(base_path, entry, package_store)
          full_path = File.join(base_path, entry.path)
          case entry.type
          when :file
            return unless File.exist?(full_path)

            package_store.add_asset(entry.path, File.binread(full_path))
          when :directory
            return unless Dir.exist?(full_path)

            Dir.glob(File.join(full_path, "**", "*")).each do |file|
              next unless File.file?(file)

              relative = file.sub(%r{\A#{Regexp.escape(base_path)}/}, "")
              package_store.add_asset(relative, File.binread(file))
            end
          end
        end

        def write_asset_entry(base_path, entry, package_store)
          case entry.type
          when :file
            content = package_store.asset(entry.path)
            return unless content

            file_path = File.join(base_path, entry.path)
            FileUtils.mkdir_p(File.dirname(file_path))
            File.binwrite(file_path, content)
          when :directory
            package_store.asset_paths
                         .select { |p| p.start_with?("#{entry.path}/") }
                         .each do |asset_path|
                           content = package_store.asset(asset_path)
                           next unless content

                           file_path = File.join(base_path, asset_path)
                           FileUtils.mkdir_p(File.dirname(file_path))
                           File.binwrite(file_path, content)
                         end
          end
        end

        # ── Helpers ──

        def set_key_from_filename(model, file_path, entry)
          key_value = model.public_send(entry.key)
          return if key_value

          basename = File.basename(file_path, ".*")
          model.public_send(:"#{entry.key}=", basename)
        end

        def extract_key(model, entry)
          model.public_send(entry.key).to_s
        end

        def sanitize_filename(key)
          key.gsub(%r{[/:#?]}, "_")
        end
      end

      class ZipTransport < Base
        def read(path, package_store, format: nil)
          definition = package_store.definition
          global_format = format

          Zip::File.open(path) do |zf|
            read_metadata_zip(zf, package_store)

            definition.model_entries.each do |entry|
              fmt_name = global_format || entry.default_format
              read_model_entry_zip(zf, entry, package_store, fmt_name)
            end

            definition.asset_entries.each do |entry|
              read_asset_entry_zip(zf, entry, package_store)
            end
          end
        end

        def write(path, package_store, formats: {})
          definition = package_store.definition
          FileUtils.mkdir_p(File.dirname(path))

          Zip::File.open(path, create: true) do |zf|
            write_metadata_zip(zf, package_store)

            definition.model_entries.each do |entry|
              fmt_name = effective_format(entry, formats)
              fmt = resolve_format(fmt_name)
              write_model_entry_zip(zf, entry, package_store, fmt)
            end

            write_assets_zip(zf, package_store)
          end
        end

        private

        # ── Metadata ──

        def read_metadata_zip(zf, package_store)
          definition = package_store.definition
          return unless definition.metadata_model && definition.metadata_file

          entry = zf.find_entry(definition.metadata_file)
          return unless entry

          fmt = format_for_file(definition.metadata_file)
          raw = entry.get_input_stream.read
          metadata = fmt.deserialize(raw, definition.metadata_model)
          package_store.metadata = metadata
        end

        def write_metadata_zip(zf, package_store)
          return unless package_store.metadata

          definition = package_store.definition
          fmt = format_for_file(definition.metadata_file)
          content = fmt.serialize(package_store.metadata)
          zf.get_output_stream(definition.metadata_file) { |f| f.write(content) }
        end

        # ── Model entries ──

        def read_model_entry_zip(zf, entry, package_store, fmt_name)
          fmt = resolve_format(fmt_name)

          if entry.file
            read_single_file_zip(zf, entry, package_store, fmt)
          else
            read_directory_zip(zf, entry, package_store, fmt)
          end
        end

        def read_single_file_zip(zf, entry, package_store, fmt)
          zip_entry = zf.find_entry(entry.file)
          return unless zip_entry

          raw = zip_entry.get_input_stream.read
          model = fmt.deserialize(raw, entry.model)
          package_store.add_model(model)
        end

        def read_directory_zip(zf, entry, package_store, fmt)
          prefix = entry.dir ? "#{entry.dir}/" : ""

          zf.entries.each do |zip_entry|
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

        def write_model_entry_zip(zf, entry, package_store, fmt)
          models = package_store.models_for(entry.model)
          return if models.empty?

          if entry.file
            content = entry.layout == :grouped ? fmt.serialize_many(models) : fmt.serialize(models.first)
            zf.get_output_stream(entry.file) { |f| f.write(content) }
          else
            write_directory_models_zip(zf, entry, models, fmt)
          end
        end

        def write_directory_models_zip(zf, entry, models, fmt)
          prefix = entry.dir ? "#{entry.dir}/" : ""

          case entry.layout
          when :grouped
            grouped = models.group_by { |m| extract_key(m, entry) }
            grouped.each do |key, group|
              filename = "#{prefix}#{key}#{fmt.extension}"
              content = fmt.serialize_many(group)
              zf.get_output_stream(filename) { |f| f.write(content) }
            end
          else
            models.each do |model|
              key = extract_key(model, entry)
              filename = "#{prefix}#{key}#{fmt.extension}"
              content = fmt.serialize(model)
              zf.get_output_stream(filename) { |f| f.write(content) }
            end
          end
        end

        # ── Assets ──

        def read_asset_entry_zip(zf, entry, package_store)
          case entry.type
          when :file
            zip_entry = zf.find_entry(entry.path)
            package_store.add_asset(entry.path, zip_entry.get_input_stream.read) if zip_entry
          when :directory
            prefix = entry.path.end_with?("/") ? entry.path : "#{entry.path}/"
            zf.entries.each do |zip_entry|
              next unless zip_entry.name.start_with?(prefix)
              next if zip_entry.name == prefix || zip_entry.name.end_with?("/")

              package_store.add_asset(zip_entry.name, zip_entry.get_input_stream.read)
            end
          end
        end

        def write_assets_zip(zf, package_store)
          package_store.asset_paths.each do |asset_path|
            content = package_store.asset(asset_path)
            zf.get_output_stream(asset_path) { |f| f.write(content) } if content
          end
        end

        # ── Helpers ──

        def set_key_from_zip_path(model, zip_path, entry, prefix)
          key_value = model.public_send(entry.key)
          return if key_value

          filename = zip_path.sub(prefix, "")
          basename = File.basename(filename, ".*")
          model.public_send(:"#{entry.key}=", basename)
        end

        def extract_key(model, entry)
          model.public_send(entry.key).to_s
        end

        def matches_format?(name, fmt)
          ext = File.extname(name)
          return true if ext == fmt.extension
          return true if fmt.extension == ".yaml" && ext == ".yml"

          false
        end
      end
    end
  end
end
