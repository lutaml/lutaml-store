# frozen_string_literal: true

require "yeptris"
require "yeptris/json"

module Lutaml
  module Store
    # JSON encoding and decoding through yeptris's native engine,
    # replacing the json gem as this library's JSON backend. The
    # interface mirrors the json gem's module functions that the store
    # uses (parse with symbolize_names, generate/dump, pretty_generate),
    # so call sites keep their shape; the error classes share the json
    # gem's names, and lexical scope resolves them to this module from
    # inside the store's namespaces.
    module JSON
      class ParserError < Error; end
      class GeneratorError < Error; end

      class << self
        def parse(source, opts = nil)
          raise ParserError, "cannot parse #{source.class}" unless source.is_a?(String)

          value = Yeptris::JSON.load(source)
          opts&.fetch(:symbolize_names, false) ? deep_symbolize(value) : value
        rescue Yeptris::Error, TypeError => e
          raise ParserError, e.message
        end

        def generate(object)
          Yeptris::JSON.dump(object)
        rescue Yeptris::Error, TypeError => e
          raise GeneratorError, e.message
        end
        alias dump generate

        def pretty_generate(object)
          pretty_value(object, 0)
        end

        private

        def deep_symbolize(value)
          case value
          when Hash then value.to_h { |k, v| [k.to_sym, deep_symbolize(v)] }
          when Array then value.map { |v| deep_symbolize(v) }
          else value
          end
        end

        def pretty_value(value, depth)
          case value
          when Hash then pretty_object(value, depth)
          when Array then pretty_array(value, depth)
          else generate(value)
          end
        end

        def pretty_object(hash, depth)
          return "{}" if hash.empty?

          inner = hash.map do |key, value|
            "#{indent(depth + 1)}#{generate(key.to_s)}: #{pretty_value(value, depth + 1)}"
          end

          "{\n#{inner.join(",\n")}\n#{indent(depth)}}"
        end

        def pretty_array(array, depth)
          return "[]" if array.empty?

          inner = array.map do |value|
            "#{indent(depth + 1)}#{pretty_value(value, depth + 1)}"
          end

          "[\n#{inner.join(",\n")}\n#{indent(depth)}]"
        end

        def indent(depth)
          "  " * depth
        end
      end
    end
  end
end
