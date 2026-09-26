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
      autoload :Xml, "lutaml/store/format/xml"

      FORMATS = {
        yaml: "Yaml",
        yamls: "Yamls",
        json: "Json",
        jsonl: "Jsonl",
        marshal: "MarshalFormat",
        xml: "Xml"
      }.freeze

      def self.resolve(format)
        entry = FORMATS[format.to_sym]
        raise UnsupportedFormatError, "Unknown format: #{format}" unless entry

        const_get(entry).new
      end

      # Self-describing content: XML documents start with "<?xml" or "<",
      # JSON with "{" or "["; everything else is YAML, the ecosystem's
      # default. Extensionless records (object-storage keys carry no
      # extension) declare their format this way instead of by guesswork
      # out of band.
      def self.guess(data)
        stripped = data.to_s.lstrip
        return :xml if stripped.start_with?("<?xml", "<")
        return :json if stripped.start_with?("{", "[")

        :yaml
      end

      def self.for_extension(ext)
        extension_map[ext] || extension_map[".#{ext.to_s.sub(/\A\./, "")}"]
      end

      private_class_method def self.extension_map
        @extension_map ||= begin
          map = {}
          FORMATS.each_value do |class_name|
            fmt = const_get(class_name).new
            ext = fmt.extension
            next if map.key?(ext)

            map[ext] = fmt
            map[".yml"] = fmt if ext == ".yaml"
          end
          map.freeze
        end
      end
    end
  end
end
