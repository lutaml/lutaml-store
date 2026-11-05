# frozen_string_literal: true

module Lutaml
  module Store
    class DatabaseStore
      # Query mechanics: in-memory sort and pagination over the record
      # union the executor gathered (stored hashes + live mirror models).
      module QueryMechanics
        def apply_sort(results, orders)
          return results if orders.empty?

          results.sort do |a, b|
            orders.reduce(0) do |cmp, o|
              break cmp unless cmp.zero?

              va = sort_field_value(a.last, o.field)
              vb = sort_field_value(b.last, o.field)

              cmp_val = if va.nil? && vb.nil?
                          0
                        elsif va.nil?
                          1
                        elsif vb.nil?
                          -1
                        else
                          va <=> vb || 0
                        end

              o.direction == :desc ? -cmp_val : cmp_val
            end
          end
        end

        def apply_pagination(results, limit, offset)
          start = offset || 0
          results = results[start..] || []
          results = results.first(limit) if limit
          results
        end
      end
    end
  end
end
