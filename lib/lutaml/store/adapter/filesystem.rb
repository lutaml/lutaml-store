# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "monitor"
require "securerandom"

module Lutaml
  module Store
    module Adapter
      # One data file per key, with an optional `.meta` file beside it.
      #
      # File names percent-encode every byte outside `[A-Za-z0-9._-]` and a
      # leading ".", so distinct keys never share a file and no name is hidden
      # or climbs out of the root. The empty key is named "%". A name longer
      # than MAX_NAME_BYTES becomes "~" + SHA-256 of the key, and the `.meta`
      # file keeps the key. Files written by 0.3.0 (lossy "_" names) are still
      # read, and are moved to the new name on the next write.
      #
      # Writers hold an exclusive lock on `<root>/.lock` (plus a per-root
      # Monitor for threads); readers hold a shared lock. Files are written
      # to a unique temp file and renamed into place.
      class FileSystem < Base
        DEFAULT_EXTENSION = ".data"
        METADATA_EXTENSION = ".meta"
        LOCK_FILE = ".lock"
        MAX_NAME_BYTES = 200
        DIGEST_PREFIX = "~"
        JSON_FORMAT = "json"
        UNSAFE_BYTE = /[^A-Za-z0-9._-]/n
        LEGACY_UNSAFE_CHAR = /[^a-zA-Z0-9._-]/
        EMPTY_KEY_NAME = "%"
        HELD_LOCKS = :lutaml_store_filesystem_locks

        @monitors = {}
        @monitors_guard = Mutex.new

        class << self
          # One Monitor per lock file, shared by every adapter instance in
          # the process, so two instances on one root exclude each other.
          def monitor_for(lock_path)
            @monitors_guard.synchronize { @monitors[lock_path] ||= ::Monitor.new }
          end
        end

        def initialize(config = {})
          super
          @root_path = @config[:path] || raise(ConfigurationError, "FileSystem adapter requires :path config")
          @extension = @config[:extension] || DEFAULT_EXTENSION
          @create_directories = @config.fetch(:create_directories, true)
          @integrity_enabled = @config.fetch(:integrity_checks, true)
          @integrity_algorithm = @config.fetch(:integrity_algorithm, "sha256")
          @lock_path = File.expand_path(File.join(@root_path, LOCK_FILE))
          @monitor = self.class.monitor_for(@lock_path)

          setup_directory_structure
        end

        def get(key)
          status, result = with_lock(:sh) { read_verified(key) }
          return result unless status == :corrupt

          # Repair writes, so it runs under the exclusive lock, never the shared one.
          with_lock(:ex) do
            status, result = read_verified(key)
            next result unless status == :corrupt

            repair_corruption(key) || raise(result)
          end
        end

        def set(key, value)
          content, format = encode_value(value)
          with_lock(:ex) { write_entry(key, content, format) }
          value
        end

        # Atomic read-modify-write: the exclusive lock is held across the
        # read, the block and the write, for threads and processes.
        def update(key)
          with_lock(:ex) do
            new_value = yield(get(key))
            set(key, new_value)
            new_value
          end
        end

        def transaction(&block)
          with_lock(:ex, &block)
        end

        def delete(key)
          with_lock(:ex) do
            file_path = existing_path_for_key(key)
            next nil unless file_path

            value = decode_value(file_safe_read(file_path), read_metadata(metadata_path_for(file_path))[:format])
            remove_entry(file_path)
            remove_legacy_entry(key)

            value
          end
        end

        def exists?(key)
          !existing_path_for_key(key).nil?
        end

        def keys
          return [] unless Dir.exist?(@root_path)

          with_lock(:sh) do
            data_files.filter_map { |file_path| key_from_path(file_path) }
          end
        end

        def all
          keys.each_with_object({}) do |key, result|
            value = get(key)
            result[key] = value unless value.nil?
          end
        end

        def clear
          return 0 unless Dir.exist?(@root_path)

          with_lock(:ex) do
            count = 0
            data_files.each do |file_path|
              File.delete(file_path)
              count += 1
            end

            Dir.glob(File.join(@root_path, "**", "*#{METADATA_EXTENSION}")).each do |file_path|
              File.delete(file_path) if File.file?(file_path)
            end

            cleanup_empty_directories(@root_path, preserve_root: true)

            count
          end
        end

        def size
          return 0 unless Dir.exist?(@root_path)

          data_files.size
        end

        def close; end

        def verify_integrity
          corrupted_keys = []
          all_keys = keys

          all_keys.each do |key|
            get(key)
          rescue Integrity::IntegrityError
            corrupted_keys << key
          end

          {
            total_keys: all_keys.size,
            corrupted_keys: corrupted_keys,
            integrity_ok: corrupted_keys.empty?
          }
        end

        def repair_corruption(key, backup_data = nil)
          with_lock(:ex) do
            file_path = existing_path_for_key(key)
            next nil unless file_path

            format = read_metadata(metadata_path_for(file_path))[:format]
            repaired_data = Integrity.repair_data(file_safe_read(file_path), backup_data)
            next nil unless Integrity.valid_data?(repaired_data)

            write_entry(key, repaired_data, format)
            decode_value(repaired_data, format)
          end
        end

        def stats
          super.merge(
            root_path: @root_path,
            extension: @extension,
            disk_usage: calculate_disk_usage
          )
        end

        private

        def setup_directory_structure
          return unless @create_directories

          FileUtils.mkdir_p(@root_path) unless Dir.exist?(@root_path)
        end

        # ── Locking ──

        # Re-entrant for the thread that already holds a lock on this root.
        # A shared lock cannot be upgraded: flock would deadlock on its own fd.
        def with_lock(mode, &block)
          held = held_lock_mode
          if held
            raise BackendError, "Cannot take an exclusive lock inside a shared lock" if mode == :ex && held == :sh

            return yield
          end

          if mode == :ex
            @monitor.synchronize { flock_lock_file(File::LOCK_EX, :ex, &block) }
          else
            flock_lock_file(File::LOCK_SH, :sh, &block)
          end
        end

        def flock_lock_file(operation, mode)
          # Nothing to read and nothing to protect before the root exists.
          return yield if mode == :sh && !Dir.exist?(@root_path)

          ensure_directory_exists(@root_path)
          File.open(@lock_path, File::RDWR | File::CREAT, 0o644) do |lock_file|
            lock_file.flock(operation)
            held_locks[@lock_path] = { mode: mode, pid: Process.pid, file: lock_file }
            yield
          ensure
            held_locks.delete(@lock_path)
          end
        end

        # A lock entry copied into a forked child is not the child's lock.
        # The child closes its copy of the lock file, so the parent's flock
        # is released when the parent closes its own descriptor.
        def held_lock_mode
          entry = held_locks[@lock_path]
          return nil unless entry
          return entry[:mode] if entry[:pid] == Process.pid

          held_locks.delete(@lock_path)
          entry[:file].close unless entry[:file].closed?
          nil
        end

        # Per thread, not per fiber: an Enumerator or Fiber that runs inside
        # a locked block re-enters the lock instead of waiting on itself.
        def held_locks
          Thread.current.thread_variable_get(HELD_LOCKS) ||
            Thread.current.thread_variable_set(HELD_LOCKS, {})
        end

        # ── Entries ──

        # Returns [:ok, value], [:missing, nil] or [:corrupt, error].
        def read_verified(key)
          file_path = existing_path_for_key(key)
          return [:missing, nil] unless file_path

          data = file_safe_read(file_path)
          metadata = read_metadata(metadata_path_for(file_path))

          begin
            verify_data_integrity(data, metadata)
          rescue Integrity::IntegrityError => e
            return [:corrupt, e]
          end

          [:ok, decode_value(data, metadata[:format])]
        end

        def write_entry(key, content, format)
          file_path = path_for_key(key)
          metadata_path = metadata_path_for(file_path)
          ensure_directory_exists(File.dirname(file_path))

          metadata = {}
          metadata[:integrity] = create_integrity_metadata(content) if @integrity_enabled
          metadata[:format] = format if format
          metadata[:key] = key.to_s if File.basename(file_path).start_with?(DIGEST_PREFIX)

          file_safe_write(file_path, content)
          if metadata.any?
            file_safe_write(metadata_path, JSON.generate(metadata))
          elsif File.exist?(metadata_path)
            File.delete(metadata_path)
          end
          remove_legacy_entry(key)
        end

        def remove_entry(file_path)
          metadata_path = metadata_path_for(file_path)
          File.delete(file_path) if File.exist?(file_path)
          File.delete(metadata_path) if File.exist?(metadata_path)
          cleanup_empty_directories(File.dirname(file_path))
        end

        def remove_legacy_entry(key)
          legacy_path = legacy_path_for_key(key)
          remove_entry(legacy_path) if legacy_path && File.exist?(legacy_path)
        end

        def encode_value(value)
          return [value, nil] if value.is_a?(String)

          [JSON.generate(value), JSON_FORMAT]
        end

        def decode_value(content, format)
          return content unless format == JSON_FORMAT

          JSON.parse(content)
        rescue JSON::ParserError
          content
        end

        # ── Paths ──

        def data_files
          Dir.glob(File.join(@root_path, "**", "*#{@extension}")).select { |path| File.file?(path) }
        end

        def path_for_key(key)
          shard_path(file_name_for_key(key))
        end

        def shard_path(name)
          if name.length >= 2
            File.join(@root_path, name[0, 2], "#{name}#{@extension}")
          else
            File.join(@root_path, "#{name}#{@extension}")
          end
        end

        # The current path, or the 0.3.0 path when only that one exists.
        def existing_path_for_key(key)
          file_path = path_for_key(key)
          return file_path if File.exist?(file_path)

          legacy_path = legacy_path_for_key(key)
          legacy_path if legacy_path && File.exist?(legacy_path)
        end

        # 0.3.0 replaced unsafe characters with "_". Nil when that name is
        # the current one, or when it would leave the root ("..").
        def legacy_path_for_key(key)
          name = key.to_s.gsub(LEGACY_UNSAFE_CHAR, "_")
          return nil if name.empty? || name.start_with?(".")

          legacy_path = shard_path(name)
          legacy_path unless legacy_path == path_for_key(key)
        end

        def metadata_path_for(data_path)
          "#{data_path.delete_suffix(@extension)}#{METADATA_EXTENSION}"
        end

        def key_from_path(file_path)
          name = File.basename(file_path, @extension)
          return decode_key(name) unless name.start_with?(DIGEST_PREFIX)

          read_metadata(metadata_path_for(file_path))[:key]
        end

        def file_name_for_key(key)
          encoded = encode_key(key)
          return encoded if encoded.bytesize <= MAX_NAME_BYTES

          "#{DIGEST_PREFIX}#{Digest::SHA256.hexdigest(key.to_s)}"
        end

        def encode_key(key)
          raw = key.to_s
          return EMPTY_KEY_NAME if raw.empty?

          encoded = raw.b.gsub(UNSAFE_BYTE) { |byte| format("%%%02X", byte.ord) }
          encoded = "%2E#{encoded[1..]}" if encoded.start_with?(".")
          encoded.force_encoding(Encoding::UTF_8)
        end

        def decode_key(name)
          return "" if name == EMPTY_KEY_NAME

          decoded = name.b.gsub(/%([0-9A-F]{2})/n) { Regexp.last_match(1).hex.chr }
          decoded.force_encoding(Encoding::UTF_8)
          decoded.valid_encoding? ? decoded : decoded.b
        end

        # ── Integrity and metadata ──

        def create_integrity_metadata(data)
          return {} unless @integrity_enabled

          Integrity.create_integrity_metadata(data, @integrity_algorithm)
        end

        def verify_data_integrity(data, metadata)
          return true unless @integrity_enabled
          return true unless metadata.is_a?(Hash) && metadata[:integrity]

          Integrity.verify_integrity_metadata(data, metadata[:integrity])
        end

        def read_metadata(metadata_path)
          return {} unless File.exist?(metadata_path)

          JSON.parse(File.read(metadata_path), symbolize_names: true)
        rescue JSON::ParserError, Errno::ENOENT
          {}
        end

        # ── Files ──

        def ensure_directory_exists(dir_path)
          return if Dir.exist?(dir_path)

          FileUtils.mkdir_p(dir_path)
        end

        def cleanup_empty_directories(dir_path, preserve_root: false)
          return if preserve_root && dir_path == @root_path
          return unless Dir.exist?(dir_path)
          return unless Dir.empty?(dir_path)

          Dir.rmdir(dir_path)

          parent_dir = File.dirname(dir_path)
          cleanup_empty_directories(parent_dir, preserve_root: preserve_root) if parent_dir != dir_path
        end

        def file_safe_read(file_path)
          content = File.binread(file_path)
          utf8 = content.dup.force_encoding(Encoding::UTF_8)
          utf8.valid_encoding? ? utf8 : content
        rescue StandardError => e
          raise BackendError, "Failed to read file #{file_path}: #{e.message}"
        end

        # The temp name is unique per call, so concurrent writers never share
        # a temp file; rename makes the new content visible atomically.
        def file_safe_write(file_path, content)
          temp_path = "#{file_path}.tmp.#{Process.pid}.#{SecureRandom.hex(6)}"

          File.open(temp_path, "wb") do |file|
            file.write(content)
            file.fsync
          end

          File.rename(temp_path, file_path)
        rescue StandardError => e
          FileUtils.rm_f(temp_path)
          raise BackendError, "Failed to write file #{file_path}: #{e.message}"
        end

        def calculate_disk_usage
          return 0 unless Dir.exist?(@root_path)

          data_files.sum { |file_path| File.size(file_path) }
        end
      end
    end
  end
end
