# frozen_string_literal: true

require "cgi"
require "fileutils"
require "json"

module Lutaml
  module Store
    # Pulls a source into a local package directory — the GCR-style shape:
    #
    #   <into>[/<collection>]/
    #     manifest.json
    #     entries/<percent-encoded-key>
    #
    # The result is readable by Source::Directory, is the local-cache layout
    # Repository uses, and is byte-compatible with the TypeScript
    # implementation's LocalStore (conformance fixtures pin this).
    #
    # Pulls are incremental and digest-verified: entries whose local sha256
    # already matches are not rewritten; a mismatched local entry is
    # re-fetched. Digest mismatches against the source manifest are hard
    # errors — never silently accepted.
    module Mirror
      class IntegrityError < Error; end

      class << self
        # @param source [Source::Base]
        # @param into [String] directory to place the package in
        # @param collection [String, nil] optional subdirectory of +into+
        # @param force [Boolean] re-write entries even when digests match
        # @return [Source::Directory] a source over the written package
        def pull(source, into:, collection: nil, force: false)
          manifest = source.manifest
          root = collection ? ::File.join(into, collection) : into
          entries_dir = ::File.join(root, "entries")
          FileUtils.mkdir_p(entries_dir)

          pulled = 0
          entries = manifest.entries.map do |entry|
            body = source.read(entry.key)
            unless entry.matches?(body)
              raise IntegrityError,
                    "digest mismatch for #{entry.key.inspect}: manifest declares " \
                    "#{entry.digest}, source returned #{entry.digest_for(body)}"
            end

            location = entry.location || "entries/#{Source.encode_key(entry.key)}"
            path = ::File.join(root, location)
            write_if_changed(path, body, force)
            pulled += 1
            Manifest::Entry.new(
              key: entry.key, location: location,
              digest: entry.digest_for(body), shard: entry.shard,
              metadata: entry.metadata
            )
          end

          local = Manifest.build(entries, shards: manifest.shards)
          ::File.write(::File.join(root, "manifest.json"), JSON.pretty_generate(local.to_hash))

          Source.for(:directory, path: root)
        end

        # Packs an existing package directory (as written by .pull) into a
        # distributable .zip — the "downloaded official package" artifact.
        # Source::Zip reads it back with no unpacking step.
        #
        # @param package_dir [String] a directory containing manifest.json + entries/
        # @param to [String] the .zip path to write
        # @return [String] the path written
        def pack(package_dir, to:)
          require "zip"
          FileUtils.mkdir_p(::File.dirname(to))
          ::Zip::File.open(to, create: true) do |zip|
            Dir["#{package_dir}/**/*"].sort.each do |path|
              next if ::File.directory?(path)

              zip.add(path.delete_prefix("#{package_dir}/"), path)
            end
          end
          to
        end

        private

        def write_if_changed(path, body, force)
          if !force && ::File.file?(path) && ::File.binread(path) == body
            return
          end

          ::File.binwrite(path, body)
        end
      end
    end
  end
end
