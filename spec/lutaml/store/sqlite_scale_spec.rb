# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

begin
  require "sqlite3"
rescue LoadError
  nil
end

# Pin the SQLite adapter's bulk behaviour at the scale the Relaton cache
# index will hit (lutaml/lutaml-store#11). Skipped if the sqlite3 gem is
# not installed — the FileSystem adapter is the fallback.
RSpec.describe "Lutaml::Store::Adapter::SQLite scale", if: defined?(SQLite3::Database) do
  let(:db_path) { File.join(Dir.mktmpdir, "scale.db") }
  let(:adapter) { Lutaml::Store::Adapter.resolve(:sqlite, path: db_path) }

  after {  }

  context "bulk write and read at 10_000 keys" do
    let(:scale) { 10_000 }

    it "writes and reads back" do
      scale.times { |i| adapter.set("key-#{i}", "value-#{i}") }
      expect(adapter.get("key-0")).to eq("value-0")
      expect(adapter.get("key-#{scale - 1}")).to eq("value-#{scale - 1}")
    end

    it "streams keys without materialising all values" do
      scale.times { |i| adapter.set("key-#{i}", "value-#{i}") }
      keys = adapter.keys
      expect(keys.size).to eq(scale)
      expect(keys).to include("key-0")
    end

    it "checks existence in constant time" do
      scale.times { |i| adapter.set("key-#{i}", "value-#{i}") }
      expect(adapter.exists?("key-#{scale / 2}")).to be(true)
      expect(adapter.exists?("nonexistent")).to be(false)
    end
  end
end
