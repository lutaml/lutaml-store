# frozen_string_literal: true

module Lutaml
  module Store
    module PackageTransport
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
                fmt.deserialize_many(raw, entry.model).each do |m|
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
          content = entry.layout == :grouped ? fmt.serialize_many(models) : fmt.serialize(models.first)
          file_path = File.join(base_path, entry.file)
          FileUtils.mkdir_p(File.dirname(file_path))
          File.write(file_path, content, encoding: "utf-8")
        end

        def write_directory_models(base_path, entry, models, fmt)
          dir = entry.dir ? File.join(base_path, entry.dir) : base_path
          FileUtils.mkdir_p(dir)

          case entry.layout
          when :grouped
            models.group_by { |m| extract_key(m, entry) }.each do |key, group|
              file_path = File.join(dir, "#{sanitize_filename(key)}#{fmt.extension}")
              File.write(file_path, fmt.serialize_many(group), encoding: "utf-8")
            end
          else
            models.each do |model|
              key = extract_key(model, entry)
              file_path = File.join(dir, "#{sanitize_filename(key)}#{fmt.extension}")
              File.write(file_path, fmt.serialize(model), encoding: "utf-8")
            end
          end
        end

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
      end
    end
  end
end
