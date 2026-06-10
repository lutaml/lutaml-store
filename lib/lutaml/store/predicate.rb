# frozen_string_literal: true

module Lutaml
  module Store
    module Predicate
      class Base
        attr_reader :field, :value

        def initialize(field, value = nil)
          @field = field.to_sym
          @value = value
        end

        def match?(_target)
          raise NotImplementedError
        end

        def negate
          raise NotImplementedError
        end

        def hash_evaluable?(hash_data)
          hash_data.key?(@field.to_s)
        end

        private

        def extract(target)
          target.is_a?(Hash) ? target[@field.to_s] : target.public_send(@field)
        end
      end

      class Equal < Base
        def match?(target)
          extract(target) == @value
        end

        def negate
          NotEqual.new(@field, @value)
        end
      end

      class NotEqual < Base
        def match?(target)
          extract(target) != @value
        end

        def negate
          Equal.new(@field, @value)
        end
      end

      class GreaterThan < Base
        def match?(target)
          val = extract(target)
          return false if val.nil?

          val > @value
        end

        def negate
          LessThanOrEqual.new(@field, @value)
        end
      end

      class LessThan < Base
        def match?(target)
          val = extract(target)
          return false if val.nil?

          val < @value
        end

        def negate
          GreaterThanOrEqual.new(@field, @value)
        end
      end

      class GreaterThanOrEqual < Base
        def match?(target)
          val = extract(target)
          return false if val.nil?

          val >= @value
        end

        def negate
          LessThan.new(@field, @value)
        end
      end

      class LessThanOrEqual < Base
        def match?(target)
          val = extract(target)
          return false if val.nil?

          val <= @value
        end

        def negate
          GreaterThan.new(@field, @value)
        end
      end

      class Between < Base
        def match?(target)
          val = extract(target)
          return false if val.nil?

          @value.cover?(val)
        end

        def negate
          NotBetween.new(@field, @value)
        end
      end

      class NotBetween < Base
        def match?(target)
          val = extract(target)
          return false if val.nil?

          !@value.cover?(val)
        end

        def negate
          Between.new(@field, @value)
        end
      end

      class In < Base
        def match?(target)
          val = extract(target)
          return false if val.nil?

          @value.include?(val)
        end

        def negate
          NotIn.new(@field, @value)
        end
      end

      class NotIn < Base
        def match?(target)
          val = extract(target)
          return false if val.nil?

          !@value.include?(val)
        end

        def negate
          In.new(@field, @value)
        end
      end

      class Matches < Base
        def match?(target)
          val = extract(target)
          return false if val.nil?

          @value.match?(val.to_s)
        end

        def negate
          NotMatches.new(@field, @value)
        end
      end

      class NotMatches < Base
        def match?(target)
          val = extract(target)
          return true if val.nil?

          !@value.match?(val.to_s)
        end

        def negate
          Matches.new(@field, @value)
        end
      end

      class Nil < Base
        def match?(target)
          extract(target).nil?
        end

        def negate
          NotNil.new(@field)
        end
      end

      class NotNil < Base
        def match?(target)
          !extract(target).nil?
        end

        def negate
          Nil.new(@field)
        end
      end

      # ── Factory methods ──

      def self.gt(field, value)
        GreaterThan.new(field, value)
      end

      def self.lt(field, value)
        LessThan.new(field, value)
      end

      def self.gte(field, value)
        GreaterThanOrEqual.new(field, value)
      end

      def self.lte(field, value)
        LessThanOrEqual.new(field, value)
      end

      def self.not(field, value)
        NotEqual.new(field, value)
      end

      def self.matches(field, pattern)
        Matches.new(field, pattern)
      end

      def self.nil(field)
        Nil.new(field)
      end

      def self.not_nil(field)
        NotNil.new(field)
      end

      def self.build_from_hash(conditions)
        conditions.map do |field, value|
          case value
          when Range then Between.new(field, value)
          when Array then In.new(field, value)
          else Equal.new(field, value)
          end
        end
      end
    end
  end
end
