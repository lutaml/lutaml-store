# frozen_string_literal: true

module Lutaml
  module Store
    # Read-only views over a LutaML data repository.
    #
    # A source answers four questions about a remote or local collection of
    # LutaML records: does a key exist, what are its bytes, which keys exist,
    # and what does the repository's manifest declare. Sources never write.
    #
    # Selection is explicit: `Source.for(type, options)` raises
    # `ConfigurationError` for a missing option — there is no discovery,
    # no environment guessing and no fallback between sources. Consumers
    # compose sources with {Repository} for caching policies.
    module Source
      autoload :Base, "lutaml/store/source/base"
      autoload :Directory, "lutaml/store/source/directory"
      autoload :Zip, "lutaml/store/source/zip"
      autoload :Https, "lutaml/store/source/https"
      autoload :Rest, "lutaml/store/source/rest"

      TYPES = {
        directory: "Directory",
        zip: "Zip",
        https: "Https",
        rest: "Rest"
      }.freeze

      class << self
        # Builds an explicitly configured source.
        #
        # @param type [Symbol] one of {TYPES}
        # @param options [Hash] passed to the source class
        # @return [Source::Base]
        def for(type, **options)
          name = TYPES[type.to_sym]
          raise ConfigurationError, "unknown source type: #{type.inspect}" unless name

          Source.const_get(name).new(**options)
        end

        # A key is percent-encoded into exactly one path segment, so storage
        # keys like "RFC 3986" or "ISO/IEC DIR 1" map to one file each on
        # every platform. The manifest keeps the real key.
        def encode_key(key)
          CGI.escape(key.to_s)
        end

        def decode_key(segment)
          CGI.unescape(segment.to_s)
        end
      end
    end
  end
end
