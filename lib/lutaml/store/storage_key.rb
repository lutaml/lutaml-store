# frozen_string_literal: true

module Lutaml
  module Store
    class StorageKey
      attr_reader :class_name, :key_value

      def initialize(class_name, key_value)
        @class_name = class_name.to_s
        @key_value = key_value.to_s
      end

      def to_s
        "#{@class_name}:#{@key_value}"
      end

      alias to_str to_s

      def self.parse(string)
        str = string.to_s
        sep = str.index(/(?<!:):(?!:)/)
        return new("", str) unless sep

        new(str[0...sep], str[sep + 1..])
      end

      def eql?(other)
        other.is_a?(StorageKey) && to_s == other.to_s
      end

      def hash
        to_s.hash
      end

      def ==(other)
        to_s == other.to_s
      end
    end
  end
end
