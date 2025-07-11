# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"

module Lutaml
  module Store
    module Adapter
      class FileSystem < Base
        DEFAULT_EXTENSION = ".data"
        METADATA_EXTENSION = ".meta"

        def initialize(config = {})
          super
          @root_path = @config[:path] || raise(ConfigurationError, "FileSystem adapter requires :path config")
          @extension = @config[:extension] || DEFAULT_EXTENSION
          @create_directories = @config.fetch(:create_directories, true)

          setup_directory_structure
        end

        def save(key, data, metadata = {})
          file_path = path_for_key(key)
          ensure_directory_exists(File.dirname(file_path))

          # Wrap with integrity metadata
          full_metadata = wrap_with_integrity(data, metadata)

          file_safe_write(file_path, data)
          write_metadata(key, full_metadata) if full_metadata.any?
          data
        end

        def load(key)
          file_path = path_for_key(key)
          return nil unless File.exist?(file_path)

          data = file_safe_read(file_path)
          metadata = read_metadata(key)

          # Verify integrity if enabled
          begin
            verify_data_integrity(data, metadata)
          rescue Integrity::IntegrityError => e
            # Try to repair if possible
            repaired_data = repair_corruption(key)
            return repaired_data if repaired_data
            raise e
          end

          data
        end

        def get(key)
          load(key)
        end

        def set(key, value)
          save(key, value)
        end

        def delete(key)
          file_path = path_for_key(key)
          metadata_path = metadata_path_for_key(key)

          return nil unless File.exist?(file_path)

          value = file_safe_read(file_path)
          File.delete(file_path)
          File.delete(metadata_path) if File.exist?(metadata_path)

          # Clean up empty directories
          cleanup_empty_directories(File.dirname(file_path))

          value
        end

        def exists?(key)
          File.exist?(path_for_key(key))
        end

        def keys
          return [] unless Dir.exist?(@root_path)

          Dir.glob(File.join(@root_path, "**", "*#{@extension}")).map do |file_path|
            key_from_path(file_path) if File.file?(file_path)
          end.compact
        end

        def all
          result = {}

          Dir.glob(File.join(@root_path, "**", "*#{@extension}")).each do |file_path|
            next unless File.file?(file_path)

            key = key_from_path(file_path)
            value = load(key) # Use load to get integrity checking
            result[key] = value if value
          end

          result
        end

        def clear
          return 0 unless Dir.exist?(@root_path)

          count = 0
          Dir.glob(File.join(@root_path, "**", "*#{@extension}")).each do |file_path|
            if File.file?(file_path)
              File.delete(file_path)
              count += 1
            end
          end

          # Also clean up metadata files
          Dir.glob(File.join(@root_path, "**", "*#{METADATA_EXTENSION}")).each do |file_path|
            File.delete(file_path) if File.file?(file_path)
          end

          # Clean up empty directories
          cleanup_empty_directories(@root_path, preserve_root: true)

          count
        end

        def size
          return 0 unless Dir.exist?(@root_path)

          Dir.glob(File.join(@root_path, "**", "*#{@extension}")).count { |path| File.file?(path) }
        end

        def close
          # Nothing to close for filesystem adapter
        end

        def verify_integrity
          corrupted_keys = []

          keys.each do |key|
            begin
              load(key) # This will verify integrity
            rescue Integrity::IntegrityError
              corrupted_keys << key
            end
          end

          {
            total_keys: keys.size,
            corrupted_keys: corrupted_keys,
            integrity_ok: corrupted_keys.empty?
          }
        end

        def repair_corruption(key, backup_data = nil)
          file_path = path_for_key(key)
          return nil unless File.exist?(file_path)

          corrupted_data = file_safe_read(file_path)

          # Try to repair the data
          repaired_data = Integrity.repair_data(corrupted_data, backup_data)

          if Integrity.valid_data?(repaired_data)
            # Save the repaired data
            save(key, repaired_data)
            return repaired_data
          end

          nil
        end

        def stats
          super.merge({
            root_path: @root_path,
            extension: @extension,
            disk_usage: calculate_disk_usage
          })
        end

        private

        def validate_config!
          unless @config[:path]
            raise ConfigurationError, "FileSystem adapter requires :path configuration"
          end
        end

        def setup_directory_structure
          return unless @create_directories

          FileUtils.mkdir_p(@root_path) unless Dir.exist?(@root_path)
        end

        def path_for_key(key)
          # Create a safe file path from the key
          safe_key = sanitize_key(key)

          # Use first two characters for directory structure to avoid too many files in one directory
          if safe_key.length >= 2
            subdir = safe_key[0, 2]
            File.join(@root_path, subdir, "#{safe_key}#{@extension}")
          else
            File.join(@root_path, "#{safe_key}#{@extension}")
          end
        end

        def metadata_path_for_key(key)
          data_path = path_for_key(key)
          data_path.sub(@extension, METADATA_EXTENSION)
        end

        def key_from_path(file_path)
          relative_path = file_path.sub(@root_path, "").sub(/^\//, "")

          # Remove directory structure and extension
          key = File.basename(relative_path, @extension)

          # Reverse sanitization if needed
          key
        end

        def sanitize_key(key)
          # Convert key to safe filename
          # Replace unsafe characters with underscores
          key.to_s.gsub(/[^a-zA-Z0-9._-]/, "_")
        end

        def write_metadata(key, metadata)
          return unless metadata.any?

          metadata_path = metadata_path_for_key(key)
          ensure_directory_exists(File.dirname(metadata_path))

          File.write(metadata_path, JSON.generate(metadata))
        end

        def read_metadata(key)
          metadata_path = metadata_path_for_key(key)
          return {} unless File.exist?(metadata_path)

          begin
            JSON.parse(File.read(metadata_path), symbolize_names: true)
          rescue JSON::ParserError
            {}
          end
        end

        def ensure_directory_exists(dir_path)
          return if Dir.exist?(dir_path)

          FileUtils.mkdir_p(dir_path)
        end

        def cleanup_empty_directories(dir_path, preserve_root: false)
          return if preserve_root && dir_path == @root_path
          return unless Dir.exist?(dir_path)
          return unless Dir.empty?(dir_path)

          Dir.rmdir(dir_path)

          # Recursively clean up parent directories
          parent_dir = File.dirname(dir_path)
          cleanup_empty_directories(parent_dir, preserve_root: preserve_root) if parent_dir != dir_path
        end

        def file_safe_read(file_path)
          File.open(file_path, "rb") do |file|
            file.flock(File::LOCK_SH)
            file.read
          end
        rescue => e
          raise BackendError, "Failed to read file #{file_path}: #{e.message}"
        end

        def file_safe_write(file_path, content)
          temp_path = "#{file_path}.tmp.#{Process.pid}"

          File.open(temp_path, "wb") do |file|
            file.flock(File::LOCK_EX)
            file.write(content)
            file.fsync
          end

          File.rename(temp_path, file_path)
        rescue => e
          File.delete(temp_path) if File.exist?(temp_path)
          raise BackendError, "Failed to write file #{file_path}: #{e.message}"
        end

        def calculate_disk_usage
          return 0 unless Dir.exist?(@root_path)

          total_size = 0
          Dir.glob(File.join(@root_path, "**", "*#{@extension}")).each do |file_path|
            total_size += File.size(file_path) if File.file?(file_path)
          end

          total_size
        end
      end
    end
  end
end
