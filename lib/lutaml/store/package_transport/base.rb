# frozen_string_literal: true

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
          Format.for_extension(File.extname(filename)) || Format.resolve(:yaml)
        end

        def extract_key(model, entry)
          model.public_send(entry.key).to_s
        end

        def set_key_from_filename(model, filename, entry)
          return if model.public_send(entry.key)

          basename = File.basename(filename, ".*")
          model.public_send(:"#{entry.key}=", basename)
        end

        def sanitize_filename(key)
          key.gsub(%r{[/:#?]}, "_")
        end
      end
    end
  end
end
