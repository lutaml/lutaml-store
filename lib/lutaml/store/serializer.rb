# frozen_string_literal: true

require "json"
require "yaml"

module Lutaml
  module Store
    class Serializer
      SUPPORTED_FORMATS = %i[marshal hash json yaml xml toml].freeze

      def self.serialize(object, format = :marshal)
        case format
        when :marshal
          Marshal.dump(object)
        when :hash
          serialize_hash(object)
        when :json
          serialize_json(object)
        when :yaml
          serialize_yaml(object)
        when :xml
          serialize_xml(object)
        when :toml
          serialize_toml(object)
        else
          raise ArgumentError, "Unsupported format: #{format}. Supported: #{SUPPORTED_FORMATS.join(', ')}"
        end
      end

      def self.deserialize(data, format = :marshal, klass = nil)
        case format
        when :marshal
          Marshal.load(data)
        when :hash
          deserialize_hash(data, klass)
        when :json
          deserialize_json(data, klass)
        when :yaml
          deserialize_yaml(data, klass)
        when :xml
          deserialize_xml(data, klass)
        when :toml
          deserialize_toml(data, klass)
        else
          raise ArgumentError, "Unsupported format: #{format}. Supported: #{SUPPORTED_FORMATS.join(', ')}"
        end
      end

      def self.detect_format(data)
        return :marshal if data.start_with?("\x04\x08")
        return :json if data.strip.start_with?("{", "[")
        return :yaml if data.include?("---") || data.include?(": ")
        return :xml if data.strip.start_with?("<")
        return :toml if data.include?(" = ") || data.include?("[")

        :hash # fallback
      end

      private

      def self.serialize_hash(object)
        if object.respond_to?(:to_h)
          YAML.dump(object.to_h)
        else
          YAML.dump(object)
        end
      end

      def self.deserialize_hash(data, klass)
        hash = YAML.safe_load(data, permitted_classes: [Symbol])
        if klass && klass.respond_to?(:from_hash)
          klass.from_hash(hash)
        else
          hash
        end
      end

      def self.serialize_json(object)
        if object.respond_to?(:to_json)
          # For polymorphic support, wrap with type information
          if object.respond_to?(:to_h)
            wrapped = {
              "_type" => object.class.name,
              "_data" => object.to_h
            }
            JSON.generate(wrapped)
          else
            object.to_json
          end
        else
          JSON.generate(object)
        end
      end

      def self.deserialize_json(data, klass)
        hash = JSON.parse(data)

        # Check if this is polymorphic data with type information
        if hash.is_a?(Hash) && hash.key?("_type") && hash.key?("_data")
          type_name = hash["_type"]
          data_hash = hash["_data"]

          # Try to find the class by name
          begin
            target_class = Object.const_get(type_name)
            if target_class.respond_to?(:from_hash)
              return target_class.from_hash(data_hash)
            end
          rescue NameError
            # Class not found, fall back to hash
          end

          return data_hash
        end

        # Standard deserialization
        if klass && klass.respond_to?(:from_hash)
          klass.from_hash(hash)
        else
          hash
        end
      end

      def self.serialize_yaml(object)
        if object.respond_to?(:to_yaml)
          object.to_yaml
        else
          YAML.dump(object)
        end
      end

      def self.deserialize_yaml(data, klass)
        hash = YAML.safe_load(data, permitted_classes: [Symbol])
        if klass && klass.respond_to?(:from_hash)
          klass.from_hash(hash)
        else
          hash
        end
      end

      def self.serialize_xml(object)
        if object.respond_to?(:to_xml)
          object.to_xml
        else
          raise ArgumentError, "Object does not support XML serialization"
        end
      end

      def self.deserialize_xml(data, klass)
        if klass && klass.respond_to?(:from_xml)
          klass.from_xml(data)
        else
          raise ArgumentError, "Class does not support XML deserialization"
        end
      end

      def self.serialize_toml(object)
        if object.respond_to?(:to_toml)
          object.to_toml
        else
          raise ArgumentError, "Object does not support TOML serialization"
        end
      end

      def self.deserialize_toml(data, klass)
        if klass && klass.respond_to?(:from_toml)
          klass.from_toml(data)
        else
          raise ArgumentError, "Class does not support TOML deserialization"
        end
      end
    end
  end
end
