# frozen_string_literal: true

module Lutaml
  module Store
    # Lazy, chainable query object — inspired by ActiveRecord::Relation.
    # Collects predicates, sort orders, limit, and offset. Nothing executes
    # until a terminal method is called (to_a, each, first, count, etc.).
    class Query
      include Enumerable

      attr_reader :model_class, :predicates, :orders, :limit_value, :offset_value

      def initialize(store, model_class, predicates: [], orders: [],
                     limit_value: nil, offset_value: nil)
        @store = store
        @model_class = model_class
        @predicates = predicates.dup.freeze
        @orders = orders.dup.freeze
        @limit_value = limit_value
        @offset_value = offset_value
      end

      # ── Chainable methods (return new Query) ──

      def where(*predicates_or_conditions, **kwargs)
        conditions = kwargs
        new_predicates = []

        predicates_or_conditions.each do |arg|
          if arg.is_a?(Predicate::Base)
            new_predicates << arg
          elsif arg.is_a?(Hash)
            conditions = conditions.merge(arg)
          else
            raise ArgumentError, "where accepts Predicate objects or Hash conditions, got #{arg.class}"
          end
        end

        new_predicates.concat(Predicate.build_from_hash(conditions)) unless conditions.empty?
        chain(predicates: @predicates + new_predicates)
      end

      def not(conditions = {}, **kwargs)
        conditions = conditions.merge(kwargs)
        negated = Predicate.build_from_hash(conditions).map(&:negate)
        chain(predicates: @predicates + negated)
      end

      def order(*specs)
        new_orders = parse_order_specs(specs)
        chain(orders: @orders + new_orders)
      end

      def limit(count)
        chain(limit_value: count)
      end

      def offset(count)
        chain(offset_value: count)
      end

      def reverse_order
        reversed = @orders.map { |o| Order.new(o.field, o.direction == :asc ? :desc : :asc) }
        chain(orders: reversed)
      end

      # ── Terminal methods (execute the query) ──

      def to_a
        @to_a_result ||= @store.execute_query(self)
      end

      def each(&block)
        to_a.each(&block)
      end

      def first
        self.class.new(@store, @model_class, predicates: @predicates,
                                             orders: @orders, limit_value: 1,
                                             offset_value: @offset_value).to_a.first
      end

      def last
        reversed = @orders.map { |o| Order.new(o.field, o.direction == :asc ? :desc : :asc) }
        self.class.new(@store, @model_class, predicates: @predicates,
                                             orders: reversed, limit_value: 1,
                                             offset_value: @offset_value).to_a.first
      end

      def find_by(**conditions)
        where(**conditions).first
      end

      def find_by!(**conditions)
        result = find_by(**conditions)
        raise ModelNotRegisteredError, "No #{@model_class} found matching #{conditions}" unless result

        result
      end

      def count
        return to_a.size if @limit_value || @offset_value

        @store.count_query(self)
      end

      alias size count
      alias length count

      def exists?
        self.class.new(@store, @model_class, predicates: @predicates,
                                             orders: [], limit_value: 1, offset_value: nil).to_a.any?
      end

      def empty?
        !exists?
      end

      def any?
        exists?
      end

      def none?
        !exists?
      end

      def one?
        self.class.new(@store, @model_class, predicates: @predicates,
                                             orders: [], limit_value: 2, offset_value: nil).to_a.size == 1
      end

      def many?
        self.class.new(@store, @model_class, predicates: @predicates,
                                             orders: [], limit_value: 2, offset_value: nil).to_a.size > 1
      end

      # ── Calculation shortcuts ──

      def pluck(*fields)
        to_a.map do |model|
          if fields.size == 1
            model.public_send(fields.first)
          else
            fields.map { |f| model.public_send(f) }
          end
        end
      end

      def distinct(field = nil)
        if field
          to_a.map { |m| m.public_send(field) }.uniq
        else
          to_a.uniq
        end
      end

      def sum(field)
        to_a.sum { |m| m.public_send(field) }
      end

      def average(field)
        values = to_a.map { |m| m.public_send(field) }.compact
        return 0.0 if values.empty?

        values.sum.to_f / values.size
      end

      def minimum(field)
        to_a.min_by { |m| m.public_send(field) }
      end

      def maximum(field)
        to_a.max_by { |m| m.public_send(field) }
      end

      # ── Batch processing ──

      def find_each(batch_size: 1000, &block)
        raise ArgumentError, "find_each does not support limit/offset" if @limit_value || @offset_value

        cursor = nil
        loop do
          batch = @store.fetch_batch(self, after: cursor, limit: batch_size)
          break if batch.empty?

          batch.each(&block)
          cursor = @store.last_storage_key_from(batch, @model_class)
        end
      end

      def in_batches(of: 1000)
        raise ArgumentError, "in_batches does not support limit/offset" if @limit_value || @offset_value

        cursor = nil
        loop do
          batch = @store.fetch_batch(self, after: cursor, limit: of)
          break if batch.empty?

          yield batch
          cursor = @store.last_storage_key_from(batch, @model_class)
        end
      end

      # ── Scopes ──

      def apply(scope_name, *args, **kwargs)
        scope_body = @store.scope_for(scope_name)
        instance_exec(*args, **kwargs, &scope_body)
      end

      def inspect
        parts = [@model_class.to_s]
        parts << "WHERE #{@predicates.map(&:inspect).join(" AND ")}" if @predicates.any?
        parts << "ORDER BY #{@orders.map { |o| "#{o.field} #{o.direction}" }.join(", ")}" if @orders.any?
        parts << "LIMIT #{@limit_value}" if @limit_value
        parts << "OFFSET #{@offset_value}" if @offset_value
        "#<Query #{parts.join(" ")}>"
      end

      private

      def chain(**overrides)
        self.class.new(
          @store,
          @model_class,
          predicates: overrides.fetch(:predicates, @predicates),
          orders: overrides.fetch(:orders, @orders),
          limit_value: overrides.fetch(:limit_value, @limit_value),
          offset_value: overrides.fetch(:offset_value, @offset_value)
        )
      end

      def parse_order_specs(specs)
        orders = []
        i = 0
        while i < specs.size
          item = specs[i]
          case item
          when Hash
            item.each { |field, dir| orders << Order.new(field, dir) }
          when Symbol, String
            next_val = specs[i + 1]
            if next_val.is_a?(Symbol) && %i[asc desc].include?(next_val)
              orders << Order.new(item, next_val)
              i += 1
            else
              orders << Order.new(item, :asc)
            end
          end
          i += 1
        end
        orders
      end
    end

    # Sort specification value object
    Order = Struct.new(:field, :direction)
  end
end
