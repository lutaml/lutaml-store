# frozen_string_literal: true

require "sqlite3"
require "json"

module Lutaml
  module Store
    module Adapter
      class Sqlite < Base
        DEFAULT_TABLE_NAME = "lutaml_store"

        def initialize(config = {})
          super
          @db_path = @config[:path] || raise(ConfigurationError, "SQLite adapter requires :path config")
          @table_name = @config[:table_name] || DEFAULT_TABLE_NAME
          @timeout = @config[:timeout] || 30_000

          setup_database
        end

        def get(key)
          execute_query("SELECT value FROM #{@table_name} WHERE key = ?", [key]) do |row|
            value = row[0]
            # Try to parse as JSON, fall back to string if it fails
            begin
              JSON.parse(value)
            rescue JSON::ParserError
              value
            end
          end
          nil
        end

        def set(key, value)
          # Serialize the value to JSON if it's not already a string
          serialized_value = value.is_a?(String) ? value : JSON.generate(value)

          execute_statement(
            "INSERT OR REPLACE INTO #{@table_name} (key, value, updated_at) VALUES (?, ?, ?)",
            [key, serialized_value, Time.now.to_f]
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
          result = execute_query("SELECT 1 FROM #{@table_name} WHERE key = ? LIMIT 1", [key]) do |row|
            return true
          end
          false
        end

        def all
          result = {}
          execute_query("SELECT key, value FROM #{@table_name}") do |row|
            result[row[0]] = row[1]
          end
          result
        end

        def clear
          count = size
          execute_statement("DELETE FROM #{@table_name}")
          count
        end

        def size
          execute_query("SELECT COUNT(*) FROM #{@table_name}") do |row|
            return row[0]
          end
          0
        end

        def keys
          result = []
          execute_query("SELECT key FROM #{@table_name}") do |row|
            result << row[0]
          end
          result
        end

        def close
          @db&.close
          @db = nil
        end

        def stats
          super.merge({
                        db_path: @db_path,
                        table_name: @table_name,
                        database_size: calculate_database_size,
                        schema_version: get_schema_version
                      })
        end

        # Bulk operations optimized for SQLite
        def bulk_set(key_value_pairs)
          @db.transaction do
            key_value_pairs.each do |key, value|
              execute_statement(
                "INSERT OR REPLACE INTO #{@table_name} (key, value, updated_at) VALUES (?, ?, ?)",
                [key, value, Time.now.to_f]
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

        private

        def validate_config!
          return if @config[:path]

          raise ConfigurationError, "SQLite adapter requires :path configuration"
        end

        def setup_database
          @db = SQLite3::Database.new(@db_path)
          @db.busy_timeout = @timeout

          # Enable WAL mode for better concurrency
          @db.execute("PRAGMA journal_mode=WAL")
          @db.execute("PRAGMA synchronous=NORMAL")
          @db.execute("PRAGMA cache_size=10000")
          @db.execute("PRAGMA temp_store=memory")

          create_table_if_not_exists
          create_indexes
        end

        def create_table_if_not_exists
          @db.execute(<<~SQL)
            CREATE TABLE IF NOT EXISTS #{@table_name} (
              key TEXT PRIMARY KEY,
              value BLOB NOT NULL,
              updated_at REAL NOT NULL DEFAULT (julianday('now'))
            )
          SQL
        end

        def create_indexes
          @db.execute("CREATE INDEX IF NOT EXISTS idx_#{@table_name}_updated_at ON #{@table_name} (updated_at)")
        end

        def execute_query(sql, params = [])
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
          execute_query("PRAGMA user_version") do |row|
            return row[0]
          end
          0
        end
      end
    end
  end
end
