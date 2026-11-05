# frozen_string_literal: true

module Lutaml
  module Store
    # A record hydrated at load time whose serialized form is never
    # computed: the transport parsed the authoritative source already, so
    # the reader serves the live model directly and the database layer
    # treats it as a stored record. A set/delete over its storage key
    # clears the mirror and hands the key back to the backend — the
    # backend stays the single writer.
    MirrorRef = Struct.new(:storage_key, :model_class_name, :reader,
                           keyword_init: true)
  end
end
