# frozen_string_literal: true

module Lutaml
  module Store
    module Format
      class Error < Lutaml::Store::Error; end
      class FormatError < Error; end
      class UnsupportedFormatError < FormatError; end

      autoload :Base, "lutaml/store/format/base"
      autoload :Yaml, "lutaml/store/format/yaml"
      autoload :Yamls, "lutaml/store/format/yamls"
      autoload :Json, "lutaml/store/format/json"
      autoload :Jsonl, "lutaml/store/format/jsonl"
      autoload :MarshalFormat, "lutaml/store/format/marshal_format"

      FORMATS = {
        yaml: "Yaml",
        yamls: "Yamls",
        json: "Json",
        jsonl: "Jsonl",
        marshal: "MarshalFormat"
      }.freeze

      def self.resolve(format)
        entry = FORMATS[format.to_sym]
        raise UnsupportedFormatError, "Unknown format: #{format}" unless entry

        const_get(entry).new
      end
    end
  end
end
