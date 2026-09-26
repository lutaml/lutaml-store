# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"

module Lutaml
  module Store
    # The uniform consumer facade: one read API whether the repository is a
    # local package, a downloaded distribution, a temp-folder cache, or the
    # cloud API. Backends are chosen by explicit composition — the
    # repository never guesses, never falls back, and never hides which
    # layer answered.
    #
    #   # cloud, with an explicit local package cache
    #   repo = Repository.new(
    #     source:   Source.for(:rest, base_url: "https://api.relaton.org",
    #                                collection: "ietf"),
    #     cache:    Source.for(:directory, path: "~/.cache/relaton/ietf"),
    #   )
    #
    #   # a downloaded official package (zip) — identical read API
    #   repo = Repository.new(source: Source.for(:zip, path: "ietf.zip"))
    #
    #   # a local GCR-style checkout
    #   repo = Repository.new(source: Source.for(:directory, path: "~/gcr/ietf"))
    #
    # Modes are explicit:
    #   :online  — read cache first, then the source (default)
    #   :offline — never touch the source; absent keys raise NotFoundError
    class Repository
      MODES = %i[online offline].freeze

      # @param source [Source::Base] the authoritative repository
      # @param cache [Source::Directory, nil] explicit read-through local
      #   package (same layout as Mirror#pull writes); nil disables caching
      # @param mode [Symbol] :online or :offline
      def initialize(source:, cache: nil, mode: :online)
        unless MODES.include?(mode)
          raise ConfigurationError, "mode must be one of #{MODES.inspect}"
        end
        if mode == :offline && cache.nil?
          raise ConfigurationError, "offline mode requires a cache source"
        end

        @source = source
        @cache = cache
        @mode = mode
      end

      # Read-through convenience constructors — still explicit about every
      # backend, just shorter.
      def self.for_cloud(base_url:, collection:, cache: nil, **source_options)
        new(source: Source.for(:rest, base_url: base_url, collection: collection,
                               **source_options), cache: cache)
      end

      def self.for_package(path, type: :directory, **source_options)
        new(source: Source.for(type, path: path, **source_options))
      end

      attr_reader :source, :cache, :mode

      # @return [String] the record's bytes
      def read(key)
        if @cache
          begin
            return @cache.read(key)
          rescue NotFoundError
            raise if @mode == :offline
          end
          body = @source.read(key)
          write_cache_entry(key, body)
          return body
        end

        @source.read(key)
      end

      # @return the model instance built by the consumer's model class
      def get(key, model_class)
        format_for(key).deserialize(read(key), model_class)
      end

      def exist?(key)
        read(key)
        true
      rescue NotFoundError
        false
      end

      def keys
        @source.keys
      end

      def each_key(&block)
        keys.each(&block)
      end

      def manifest
        @source.manifest
      end

      # Mirror the whole source into a local package (the cache layout).
      # Returns a Repository over the written package.
      def pull!(into:, collection: nil, force: false)
        pulled = Mirror.pull(@source, into: into, collection: collection, force: force)
        Repository.new(source: pulled, mode: @mode)
      end

      private

      # The write-through target is a Directory package (the Mirror layout);
      # anything else is a configuration error, not a duck-type guess. The
      # package manifest is maintained on every write so later reads —
      # including reference resolution and offline mode — see the entry.
      def write_cache_entry(key, body)
        unless @cache.is_a?(Source::Directory)
          raise ConfigurationError,
                "cache must be a Source::Directory package, got #{@cache.class}"
        end

        location = "entries/#{Source.encode_key(key)}"
        FileUtils.mkdir_p(::File.join(@cache.package_root, "entries"))
        ::File.write(::File.join(@cache.package_root, location), body, encoding: "UTF-8")

        manifest = begin
          @cache.manifest
        rescue NotFoundError
          Lutaml::Store::Manifest.build([])
        end
        entry = Manifest::Entry.new(
          key: key, location: location,
          digest: "sha256:#{Digest::SHA256.hexdigest(body)}"
        )
        entries = manifest.entries.reject { |e| e.key == key } + [entry]
        updated = Manifest.build(entries, shards: manifest.shards)
        ::File.write(
          ::File.join(@cache.package_root, "manifest.json"),
          JSON.pretty_generate(updated.to_hash)
        )
      end

      def format_for(key)
        fmt = Format.for_extension(::File.extname(key.to_s))
        fmt ||= @source.options[:default_format] &&
                Format.resolve(@source.options[:default_format])
        fmt || raise(ConfigurationError,
                     "cannot determine the format of #{key.inspect}: pass default_format:")
      end
    end
  end
end
