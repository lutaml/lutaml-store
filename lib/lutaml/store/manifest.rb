# frozen_string_literal: true

require "lutaml/model"
require "digest"

module Lutaml
  module Store
    # The enumeration document of a LutaML data repository: which keys
    # exist, where each one lives relative to the source root, and the
    # sha256 digest to verify it against.
    #
    # Sharding metadata (`shards`, `Entry#shard`) is carried but never
    # interpreted: computing "which shard holds this key" is domain logic
    # (e.g. relaton's crc32 over the pubid root number). The store only
    # enumerates.
    class Manifest
      include Lutaml::Model::Serialize

      VERSION = 1

      class Entry
        include Lutaml::Model::Serialize

        attribute :key, :string
        attribute :location, :string
        attribute :digest, :string
        attribute :shard, :integer
        attribute :metadata, :hash, default: {}

        def digest_for(body)
          "sha256:#{Digest::SHA256.hexdigest(body)}"
        end

        def matches?(body)
          return true unless digest

          digest == digest_for(body)
        end
      end

      attribute :version, :integer, default: VERSION
      attribute :generated, :string
      attribute :count, :integer, default: 0
      attribute :shards, :integer, default: 0
      attribute :entries, Manifest::Entry, collection: true, initialize_empty: true

      # @param text [String]
      # @param format [Symbol] :json or :yaml
      # @return [Manifest]
      def self.parse(text, format: :json)
        case format.to_sym
        when :json then from_json(text)
        when :yaml then from_yaml(text)
        else raise ConfigurationError, "unsupported manifest format: #{format}"
        end
      end

      def self.build(entries, generated: nil, shards: 0, version: VERSION)
        new(
          version: version,
          generated: (generated || Time.now.utc).iso8601,
          count: entries.size,
          shards: shards,
          entries: entries
        )
      end

      def keys
        entries.map(&:key)
      end

      def entry_for(key)
        entries.find { |e| e.key == key }
      end

      def key?(key)
        !entry_for(key).nil?
      end

      def shard_of_declared?
        shards.positive?
      end
    end
  end
end
