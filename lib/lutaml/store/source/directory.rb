# frozen_string_literal: true

require "cgi"
require "fileutils"

module Lutaml
  module Store
    module Source
      # A local package directory: `manifest.json` + `entries/`. This is the
      # layout {Mirror}#pull writes and what a downloaded official package
      # (GCR-style) ships — one reader for caches, distributions and
      # checkouts.
      class Directory < Base
        OPTIONS = %i[path].freeze

        attr_reader :package_root

        private

        def configure
          @path = require_option(:path)
          @package_root = @path
          FileUtils.mkdir_p(@path) unless File.directory?(@path)
        end

        def entry_path(key)
          File.join(@path, path_for(key))
        end

        public

        def read(key)
          File.read(entry_path(key), encoding: "UTF-8")
        rescue Errno::ENOENT
          raise NotFoundError, "no entry #{key.inspect} in #{@path}"
        rescue SystemCallError => e
          raise BackendError, "cannot read #{key.inspect} in #{@path}: #{e.message}"
        end

        def manifest_raw
          File.read(File.join(@path, "manifest.json"), encoding: "UTF-8")
        rescue Errno::ENOENT
          raise NotFoundError, "no manifest.json in #{@path}"
        end
      end
    end
  end
end
