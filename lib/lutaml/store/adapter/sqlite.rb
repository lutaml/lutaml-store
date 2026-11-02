# frozen_string_literal: true

require "json"
require "monitor"

module Lutaml
  module Store
    module Adapter
      class Sqlite < Base
        DEFAULT_TABLE_NAME = "lutaml_store"

        def initialize(config = {})
          super
          begin
            require "sqlite3"
          rescue LoadError
            raise ConfigurationError,
                  "sqlite3 gem is required for the SQLite adapter. Add it to your Gemfile."
          end
          @db_path = @config[:path] || raise(ConfigurationError, "SQLite adapter requires :path config")
          @table_name = @config[:table_name] || DEFAULT_TABLE_NAME
          @timeout = @config[:timeout] || 30_000
          @update_lock = ::Monitor.new

          setup_database
        end

        # ── Key-value operations ──
        #
        # Non-string values are serialized as JSON and marked in the
        # is_json column; strings are stored verbatim and returned
        # verbatim. Without the marker, a stored string that happens to
        # look like JSON (e.g. '{"x": 5}') decodes as an object.

        def get(key)
          row = query_row("SELECT value, is_json FROM #{@table_name} WHERE key = ?", [key])
          return nil unless row

          decode_value(row[0], row[1])
        end

        def set(key, value)
          is_string = value.is_a?(String)
          serialized_value = is_string ? value : JSON.generate(value)

          execute_statement(
            "INSERT OR REPLACE INTO #{@table_name} (key, value, is_json, updated_at) VALUES (?, ?, ?, ?)",
            [key, serialized_value, is_string ? 0 : 1, Time.now.to_f]
          )
          value
        end

        def delete(key)
          value = get(key)
          return nil unless value

          execute_statement("DELETE FROM #{@table_name} WHERE key = ?", [key])
          value
        end

        def exists?(key)
          execute_query_raw("SELECT 1 FROM #{@table_name} WHERE key = ? LIMIT 1", [key]) do |_row|
            return true
          end
          false
        end

        def all
          result = {}
          execute_query_raw("SELECT key, value, is_json FROM #{@table_name}") do |row|
            result[row[0]] = decode_value(row[1], row[2])
          end
          result
        end

        def clear
          count = size
          execute_statement("DELETE FROM #{@table_name}")
          count
        end

        def size
          execute_query_raw("SELECT COUNT(*) FROM #{@table_name}") do |row|
            return row[0]
          end
          0
        end

        def keys
          result = []
          execute_query_raw("SELECT key FROM #{@table_name}") do |row|
            result << row[0]
          end
          result
        end

        def close
          @db&.close
          @db = nil
        end

        def stats
          super.merge(
            db_path: @db_path,
            table_name: @table_name,
            database_size: calculate_database_size,
            schema_version: get_schema_version
          )
        end

        def bulk_set(key_value_pairs)
          @db.transaction do
            key_value_pairs.each do |key, value|
              serialized_value = value.is_a?(String) ? value : JSON.generate(value)
              execute_statement(
                "INSERT OR REPLACE INTO #{@table_name} (key, value, updated_at) VALUES (?, ?, ?)",
                [key, serialized_value, Time.now.to_f]
              )
            end
          end
        end

        def bulk_delete(keys)
          result = {}
          @db.transaction do
            keys.each do |key|
              value = get(key)
              if value
                execute_statement("DELETE FROM #{@table_name} WHERE key = ?", [key])
                result[key] = value
              else
                result[key] = nil
              end
            end
          end
          result
        end

        # ── Query operations ──

        def execute_query(query)
          sql, params = build_select_sql(query)
          results = []
          execute_query_raw(sql, params) do |row|
            results << [row[0], decode_value(row[1], row[2])]
          end
          results
        end

        def count_query(query)
          sql, params = build_count_sql(query)
          execute_query_raw(sql, params) do |row|
            return row[0]
          end
          0
        end

        def batch_query(query, after: nil, limit: 1000)
          conditions, params = build_conditions(query)

          if after
            conditions << "key > ?"
            params << after
          end

          sql = "SELECT key, value, is_json FROM #{@table_name}"
          sql += " WHERE #{conditions.join(" AND ")}" unless conditions.empty?
          sql += " ORDER BY key ASC"
          sql += " LIMIT ?"
          params << limit

          results = []
          execute_query_raw(sql, params) do |row|
            results << [row[0].to_s, decode_value(row[1], row[2])]
          end
          results
        end

        # Atomic read-modify-write. BEGIN IMMEDIATE takes the database write
        # lock before the read, so no other process can write in between;
        # the Monitor keeps threads that share this connection apart.
        def update(key, &block)
          @update_lock.synchronize do
            if @db.transaction_active?
              update_in_transaction(key, &block)
            else
              @db.transaction(:immediate) { update_in_transaction(key, &block) }
            end
          end
        rescue SQLite3::Exception => e
          raise BackendError, "Update failed: #{e.message}"
        end

        # Holds the update lock too, so a concurrent #update from another
        # thread cannot run inside this transaction.
        def transaction(&block)
          @update_lock.synchronize { @db.transaction(&block) }
        rescue SQLite3::Exception => e
          raise BackendError, "Transaction failed: #{e.message}"
        end

        private

        def update_in_transaction(key)
          new_value = yield(get(key))
          set(key, new_value)
          new_value
        end

        def setup_database
          @db = SQLite3::Database.new(@db_path)
          @db.busy_timeout = @timeout

          @db.execute("PRAGMA journal_mode=WAL")
          @db.execute("PRAGMA synchronous=NORMAL")
          @db.execute("PRAGMA cache_size=10000")
          @db.execute("PRAGMA temp_store=memory")

          create_table_if_not_exists
          migrate_schema
          create_indexes
        end

        def create_table_if_not_exists
          @db.execute(<<~SQL)
            CREATE TABLE IF NOT EXISTS #{@table_name} (
              key TEXT PRIMARY KEY,
              value BLOB NOT NULL,
              is_json INTEGER NOT NULL DEFAULT 1,
              updated_at REAL NOT NULL DEFAULT (julianday('now'))
            )
          SQL
        end

        # Databases created before the is_json column existed predate
        # format tracking: legacy rows (default is_json = 1) decode as
        # JSON when they parse, staying a string otherwise
        def migrate_schema
          columns = @db.execute("PRAGMA table_info(#{@table_name})").map do |row|
            row[1]
          end
          return if columns.include?("is_json")

          @db.execute("ALTER TABLE #{@table_name} ADD COLUMN is_json INTEGER NOT NULL DEFAULT 1")
        end

        def create_indexes
          @db.execute("CREATE INDEX IF NOT EXISTS idx_#{@table_name}_updated_at ON #{@table_name} (updated_at)")
        end

        # ── SQL generation ──

        def build_select_sql(query)
          conditions, params = build_conditions(query)

          sql = "SELECT key, value, is_json FROM #{@table_name}"
          sql += " WHERE #{conditions.join(" AND ")}" unless conditions.empty?
          sql += build_order_clause(query.orders)
          sql += build_limit_offset(query.limit_value, query.offset_value, params)

          [sql, params]
        end

        def build_count_sql(query)
          conditions, params = build_conditions(query)

          sql = "SELECT COUNT(*) FROM #{@table_name}"
          sql += " WHERE #{conditions.join(" AND ")}" unless conditions.empty?

          [sql, params]
        end

        def build_conditions(query)
          conditions = ["key LIKE ?"]
          params = ["#{query.model_class.name}:%"]

          query.predicates.each do |pred|
            clause, bind = translate_predicate(pred)
            next unless clause

            conditions << clause
            params.concat(bind)
          end

          [conditions, params]
        end

        SIMPLE_PREDICATES = {
          Predicate::Equal => "=",
          Predicate::NotEqual => "!=",
          Predicate::GreaterThan => ">",
          Predicate::LessThan => "<",
          Predicate::GreaterThanOrEqual => ">=",
          Predicate::LessThanOrEqual => "<="
        }.freeze

        def translate_predicate(pred)
          field_json = "json_extract(value, '$.#{pred.field}')"

          op = SIMPLE_PREDICATES[pred.class]
          return ["#{field_json} #{op} ?", [pred.value]] if op

          case pred
          when Predicate::Between
            ["#{field_json} BETWEEN ? AND ?", [pred.value.first, pred.value.last]]
          when Predicate::NotBetween
            ["#{field_json} NOT BETWEEN ? AND ?", [pred.value.first, pred.value.last]]
          when Predicate::In
            ["#{field_json} IN (#{in_placeholders(pred)})", pred.value]
          when Predicate::NotIn
            ["#{field_json} NOT IN (#{in_placeholders(pred)})", pred.value]
          when Predicate::Matches
            translate_matches(field_json, pred, "LIKE")
          when Predicate::NotMatches
            translate_matches(field_json, pred, "NOT LIKE")
          when Predicate::Nil
            ["#{field_json} IS NULL", []]
          when Predicate::NotNil
            ["#{field_json} IS NOT NULL", []]
          end
        end

        def in_placeholders(pred)
          pred.value.map { "?" }.join(", ")
        end

        def translate_matches(field_json, pred, op)
          pattern = pred.value.is_a?(Regexp) ? regex_to_like(pred.value) : "%#{pred.value}%"
          ["#{field_json} #{op} ?", [pattern]]
        end

        def pred_value(pred) # :nodoc:
          pred.value
        end

        def build_order_clause(orders)
          return "" if orders.empty?

          clauses = orders.map do |o|
            dir = o.direction == :desc ? "DESC" : "ASC"
            "json_extract(value, '$.#{o.field}') #{dir} NULLS LAST"
          end
          " ORDER BY #{clauses.join(", ")}"
        end

        def build_limit_offset(limit, offset, params)
          sql = ""
          if limit
            sql += " LIMIT ?"
            params << limit.to_i
          end
          if offset
            sql += " OFFSET ?"
            params << offset.to_i
          end
          sql
        end

        def regex_to_like(regex)
          source = regex.source
          pattern = source.gsub(".+", "%").gsub(".*", "%").gsub(".", "_").gsub("^", "").gsub("$", "")
          "%#{pattern}%"
        end

        # ── Raw query helpers ──

        def query_row(sql, params = [])
          execute_query_raw(sql, params) do |row|
            return row
          end
          nil
        end

        # is_json marks rows written from non-string values (the
        # default, including every pre-format-tracking row): they
        # decode as JSON when they parse. Rows written from strings
        # come back verbatim.
        def decode_value(raw, is_json)
          return raw unless is_json.to_i == 1

          JSON.parse(raw)
        rescue JSON::ParserError
          raw
        end

        def execute_query_raw(sql, params = [])
          @db.execute(sql, params) do |row|
            yield row if block_given?
          end
        rescue SQLite3::Exception => e
          raise BackendError, "SQLite query failed: #{e.message}"
        end

        def execute_statement(sql, params = [])
          @db.execute(sql, params)
        rescue SQLite3::Exception => e
          raise BackendError, "SQLite statement failed: #{e.message}"
        end

        def calculate_database_size
          return 0 unless File.exist?(@db_path)

          File.size(@db_path)
        end

        def get_schema_version
          execute_query_raw("PRAGMA user_version") do |row|
            return row[0]
          end
          0
        end
      end
    end
  end
end
