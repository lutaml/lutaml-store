# frozen_string_literal: true

require "json"

module Lutaml
  module Store
    module Source
      # A repository served by the lutaml cloud store API (the contract
      # distilled from api.relaton.org):
      #
      #   GET {base}/collections                          → collection list
      #   GET {base}/collections/{c}/manifest             → Manifest
      #   GET {base}/collections/{c}/entries/{key}        → record
      #
      # 404 is a definitive "no such key/collection" (NotFoundError); every
      # other non-2xx is a BackendError. Path shapes are fixed here so
      # server implementers have one contract — not per-client guesswork.
      class Rest < Https
        OPTIONS = %i[base_url collection].freeze

        private

        def configure
          super
          @collection = require_option(:collection)
        end

        def collection_path(suffix)
          "collections/#{Source.encode_key(@collection)}#{suffix}"
        end

        public

        def read(key)
          fetch(url_for(collection_path("/entries/#{Source.encode_key(key)}")))[:body]
        end

        def manifest_raw
          fetch(url_for(collection_path("/manifest")))[:body]
        end

        # All collections the API publishes.
        #
        # @return [Array<Hash>]
        def collections
          JSON.parse(fetch(url_for("collections"))[:body])["collections"]
        end
      end
    end
  end
end
