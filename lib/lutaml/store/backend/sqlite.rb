# frozen_string_literal: true

begin
  require "sqlite3"
rescue LoadError
  raise LoadError, "SQLite3 gem is required for SQLite backend. Add 'gem \"sqlite3\"' to your Gemfile."
end

require "thread"

module Lutaml
  module Store
    module Backend
      class Sqlite < Base
        def initialize(options = {})
          super
          @db_path = options[:path] || raise(ConfigurationError, "SQLite backend requires :path option")
          @mutex = Mutex.new
          initialize_database
        end

        def get(key)
          @mutex.synchronize do
            @db.get_first_value("SELECT value FROM store WHERE key = ?", key)
          end
        end

        def set(key, value)
          @mutex.synchronize do
            @db.execute(
              "INSERT OR REPLACE INTO store (key, value) VALUES (?, ?)",
              key, value
            )
          end
        end

        def delete(key)
          @mutex.synchronize do
            changes = @db.execute("DELETE FROM store WHERE key = ?", key)
            @db.changes > 0
          end
        end

        def exists?(key)
          @mutex.synchronize do
            @db.get_first_value("SELECT 1 FROM store WHERE key = ? LIMIT 1", key) == 1
          end
        end

        def all
          @mutex.synchronize do
            result = {}
            @db.execute("SELECT key, value FROM store") do |row|
              result[row[0]] = row[1]
            end
            result
          end
        end

        def clear
          @mutex.synchronize do
            @db.execute("DELETE FROM store")
          end
        end

        def size
          @mutex.synchronize do
            @db.get_first_value("SELECT COUNT(*) FROM store") || 0
          end
        end

        def keys
          @mutex.synchronize do
            @db.execute("SELECT key FROM store").flatten
          end
        end

        def values
          @mutex.synchronize do
            @db.execute("SELECT value FROM store").flatten
          end
        end

        def close
          @mutex.synchronize do
            @db&.close
            @db = nil
          end
        end

        private

        def initialize_database
          @db = SQLite3::Database.new(@db_path)
          @db.execute_batch(<<~SQL)
            CREATE TABLE IF NOT EXISTS store (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
              updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS idx_store_key ON store(key);

            CREATE TRIGGER IF NOT EXISTS update_timestamp
            AFTER UPDATE ON store
            FOR EACH ROW
            BEGIN
              UPDATE store SET updated_at = CURRENT_TIMESTAMP WHERE key = NEW.key;
            END;
          SQL
        end
      end
    end
  end
end
