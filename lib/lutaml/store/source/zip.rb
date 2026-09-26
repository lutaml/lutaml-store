# frozen_string_literal: true

require "zip"

module Lutaml
  module Store
    module Source
      # A packaged repository read in place from a .zip — the shape of a
      # downloaded official package. Same internal layout as
      # {Directory}: manifest.json + entries/.
      class Zip < Base
        OPTIONS = %i[path].freeze

        private

        def configure
          @path = require_option(:path)
          return if File.file?(@path)

          raise ConfigurationError, "no such package file: #{@path}"
        end

        def with_zip(&block)
          ::Zip::File.open(@path, &block)
        rescue ::Zip::Error => e
          raise BackendError, "cannot open package #{@path}: #{e.message}"
        end

        public

        def read(key)
          inner = path_for(key)
          with_zip do |zip|
            entry = zip.find_entry(inner)
            raise NotFoundError, "no entry #{key.inspect} in #{::File.basename(@path)}" unless entry

            entry.get_input_stream.read
          end
        end

        def manifest_raw
          with_zip do |zip|
            entry = zip.find_entry("manifest.json")
            raise NotFoundError, "no manifest.json in #{::File.basename(@path)}" unless entry

            entry.get_input_stream.read
          end
        end
      end
    end
  end
end
