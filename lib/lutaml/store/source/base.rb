# frozen_string_literal: true

module Lutaml
  module Store
    module Source
      # Contract shared by every source.
      #
      # Subclasses implement {#read} (bytes for one key, raising
      # NotFoundError for a definitive miss and BackendError for transport
      # trouble) and {#manifest_raw} (the manifest document). Everything
      # else — keys, existence, typed reads — composes those two.
      class Base
        OPTIONS = [].freeze

        attr_reader :options

        def initialize(**options)
          @options = options
          missing = (self.class::OPTIONS - options.keys)
          unless missing.empty?
            raise ConfigurationError,
                  "#{self.class.name.split("::").last.downcase} source requires: " \
                  "#{missing.map(&:inspect).join(", ")}"
          end
          configure
        end

        # Bytes of one record. Raises NotFoundError (definitive) or
        # BackendError (transport). Never returns nil.
        #
        # @param key [String]
        # @return [String]
        def read(_key)
          raise NotImplementedError, "#{self.class}#read"
        end

        # The manifest document as a string.
        #
        # @return [String]
        def manifest_raw
          raise NotImplementedError, "#{self.class}#manifest_raw"
        end

        # The parsed manifest, memoized.
        #
        # @return [Manifest]
        def manifest
          @manifest ||= Manifest.parse(manifest_raw, format: manifest_format)
        end

        # All keys declared by the manifest. There is deliberately no
        # fallback listing: an unenumerable source raises ConfigurationError
        # instead of guessing.
        #
        # @return [Array<String>]
        def keys
          manifest.keys
        end

        # Manifest entry for one key.
        #
        # @param key [String]
        # @return [Manifest::Entry, nil]
        def entry_for(key)
          manifest.entry_for(key)
        end

        def each_key(&block)
          return to_enum(:each_key) unless block

          keys.each(&block)
        end

        # Existence via a full read. A HEAD-based optimization may be
        # provided per source; the default is honest and uniform.
        #
        # @param key [String]
        # @return [Boolean]
        def exist?(key)
          read(key)
          true
        rescue NotFoundError
          false
        end

        # Deserialized record using the consumer's model class — the model
        # is declared by the caller, never inferred.
        #
        # @param key [String]
        # @param model_class [Class] a Lutaml::Model::Serializable subclass
        # @return the model instance
        def get(key, model_class)
          format_for(key).deserialize(read(key), model_class)
        end

        # Location of one key relative to the source. Manifest-declared
        # locations win; otherwise the single-segment convention
        # "entries/<percent-encoded key>" applies.
        #
        # @param key [String]
        # @return [String]
        def path_for(key)
          entry = manifest.entry_for(key) if manifestable?
          return entry.location if entry&.location

          "entries/#{Source.encode_key(key)}"
        end

        private

        def manifestable?
          manifest
          true
        rescue NotImplementedError, BackendError, NotFoundError
          false
        end

        def manifest_format
          @options[:manifest_format] || :json
        end

        def format_for(key)
          fmt = Format.for_extension(::File.extname(path_for(key).to_s))
          fmt ||= Format.for_extension(::File.extname(key.to_s))
          fmt ||= @options[:default_format] &&
                  Format.resolve(@options[:default_format])
          fmt || raise(ConfigurationError,
                       "cannot determine the format of #{key.inspect}: pass default_format:")
        end

        def require_option(name)
          @options[name] || raise(ConfigurationError, "#{name} is required")
        end
      end
    end
  end
end
