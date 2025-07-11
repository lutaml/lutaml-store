# frozen_string_literal: true

require "fileutils"
require "timeout"

module Lutaml
  module Store
    module Backend
      class FileSystem < Base
        attr_reader :dir

        def initialize(options = {})
          super
          @dir = options[:path] || raise(ConfigurationError, "FileSystem backend requires :path option")
          @ext = options[:extension] || "dat"
          FileUtils.mkdir_p(@dir)
        end

        def get(key)
          value = read_file(key)
          if (redirect_code = extract_redirect_code(value))
            get(redirect_code)
          else
            value
          end
        end

        def set(key, value)
          if value.nil?
            delete(key)
            return
          end

          prefix_dir = File.join(@dir, prefix(key))
          FileUtils.mkdir_p(prefix_dir) unless Dir.exist?(prefix_dir)

          extension = determine_extension(value)
          file_path = "#{filename(key)}.#{extension}"

          file_safe_write(file_path, value)
        end

        def delete(key)
          file_path = filename(key)
          found_file = search_existing_file(file_path)
          return false unless found_file

          if File.extname(found_file) == ".redirect"
            redirect_code = extract_redirect_code(read_file(key))
            delete(redirect_code) if redirect_code
          end

          File.delete(found_file)
          true
        end

        def exists?(key)
          file_path = filename(key)
          !search_existing_file(file_path).nil?
        end

        def all
          pattern = File.join(@dir, "**", "*.{#{@ext},redirect}")
          Dir.glob(pattern).sort.each_with_object({}) do |file_path, result|
            key = extract_key_from_path(file_path)
            content = File.read(file_path, encoding: "utf-8")
            result[key] = content unless content.start_with?("redirect ")
          end
        end

        def clear
          FileUtils.rm_rf(Dir.glob(File.join(@dir, "*")))
        end

        def size
          pattern = File.join(@dir, "**", "*.{#{@ext},redirect}")
          Dir.glob(pattern).count { |f| !File.read(f, encoding: "utf-8").start_with?("redirect ") }
        end

        def keys
          all.keys
        end

        def values
          all.values
        end

        private

        # Read file content by key
        def read_file(key)
          file_path = filename(key)
          found_file = search_existing_file(file_path)
          return nil unless found_file

          File.read(found_file, encoding: "utf-8")
        end

        # Generate filename from key
        def filename(key)
          # Handle prefixed keys like "prefix(code)"
          if (match = key.downcase.match(/^(?<prefix>[^(]+)\((?<code>[^)]+)/))
            prefix_part = match[:prefix]
            code_part = match[:code].gsub(/[:\s\/()]/, "_").squeeze("_")
            fn = "#{prefix_part}/#{code_part}"
          else
            fn = key.gsub(/[-:\s]/, "_")
          end

          File.join(@dir, fn.sub(/(,|_$)/, ""))
        end

        # Extract prefix from key for directory organization
        def prefix(key)
          key.downcase.match(/^[^(]+(?=\()/).to_s
        end

        # Search for existing file with different extensions
        def search_existing_file(file_path)
          ["#{file_path}.#{@ext}", "#{file_path}.redirect"].find { |f| File.exist?(f) }
        end

        # Determine file extension based on content
        def determine_extension(value)
          case value
          when /^redirect\s/ then "redirect"
          else @ext
          end
        end

        # Extract redirect code from content
        def extract_redirect_code(value)
          return nil unless value

          match = value.match(/^redirect\s+(.+)/)
          match ? match[1] : nil
        end

        # Extract key from file path (reverse of filename method)
        def extract_key_from_path(file_path)
          relative_path = file_path.sub(@dir + "/", "")
          key_part = File.basename(relative_path, ".*")
          dir_part = File.dirname(relative_path)

          if dir_part != "."
            "#{dir_part}(#{key_part})"
          else
            key_part
          end
        end

        # Thread-safe file writing with locking (adapted from Relaton::DbCache)
        def file_safe_write(file_path, content)
          File.open(file_path, File::RDWR | File::CREAT, encoding: "UTF-8") do |f|
            Timeout.timeout(10) { f.flock(File::LOCK_EX) }
            f.truncate(0)
            f.write(content)
            f.flock(File::LOCK_UN)
          end
        end
      end
    end
  end
end
