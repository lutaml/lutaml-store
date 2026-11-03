# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Lutaml::Store::Adapter::Sqlite do
  subject(:adapter) { described_class.new(path: db_path) }

  let(:db_path) { File.join(tmpdir, "store.db") }

  # Windows refuses to remove a directory that holds an open file, so
  # every database handle opened in an example is closed before
  # Dir.mktmpdir cleans up
  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
      adapter.close
      @reopened&.close
    end
  end

  let(:tmpdir) { @tmpdir }

  describe "#get and #all" do
    it "returns the same decoded value for get and all" do
      adapter.set("obj", { "a" => 1 })

      expect(adapter.get("obj")).to eq({ "a" => 1 })
      expect(adapter.all["obj"]).to eq({ "a" => 1 })
    end

    it "preserves plain strings that do not look like JSON" do
      adapter.set("str", "plain text")

      expect(adapter.get("str")).to eq "plain text"
      expect(adapter.all["str"]).to eq "plain text"
    end

    it "preserves strings that look like JSON as strings" do
      adapter.set("jsonish", '{"x": 5}')

      expect(adapter.get("jsonish")).to eq '{"x": 5}'
      expect(adapter.all["jsonish"]).to eq '{"x": 5}'
    end

    it "preserves the string/object distinction across reopen" do
      adapter.set("keep_string", '{"looks": "like json"}')
      adapter.set("keep_obj", { "real" => "object" })
      adapter.close

      reopened = described_class.new(path: db_path)
      @reopened = reopened
      expect(reopened.get("keep_string")).to eq '{"looks": "like json"}'
      expect(reopened.get("keep_obj")).to eq({ "real" => "object" })
    end
  end

  describe "legacy database migration" do
    it "adds the format column to databases created before it existed" do
      # Simulate a pre-3.0.26 database: old schema, JSON-encoded rows
      legacy_schema = <<~SQL
        CREATE TABLE lutaml_store (
          key TEXT PRIMARY KEY,
          value BLOB NOT NULL,
          updated_at REAL NOT NULL DEFAULT (julianday('now'))
        )
      SQL
      db = SQLite3::Database.new(db_path)
      db.execute(legacy_schema)
      db.execute("INSERT INTO lutaml_store (key, value) VALUES ('obj', '{\"a\":1}')")
      db.execute("INSERT INTO lutaml_store (key, value) VALUES ('str', 'plain text')")
      db.close

      @reopened = described_class.new(path: db_path)

      # Legacy rows carry no format marker: values that parse as JSON
      # decode as objects, everything else stays a string
      expect(@reopened.get("obj")).to eq({ "a" => 1 })
      expect(@reopened.get("str")).to eq "plain text"
    end
  end
end

RSpec.describe Lutaml::Store::Adapter::Sqlite, "bulk writes" do
  subject(:adapter) { described_class.new(path: db_path) }

  let(:db_path) { File.join(tmpdir, "bulk.db") }

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
      adapter.close
    end
  end

  let(:tmpdir) { @tmpdir }

  it "keeps the string/object distinction across bulk_set" do
    adapter.bulk_set(
      "jsonish" => '{"looks": "like json"}',
      "obj" => { "real" => "object" },
      "plain" => "plain text"
    )

    expect(adapter.get("jsonish")).to eq '{"looks": "like json"}'
    expect(adapter.get("obj")).to eq({ "real" => "object" })
    expect(adapter.get("plain")).to eq "plain text"
  end

  it "preserves the distinction across reopen" do
    adapter.bulk_set("jsonish" => '{"looks": "like json"}',
                     "obj" => { "real" => "object" })
    adapter.close

    reopened = described_class.new(path: db_path)
    expect(reopened.get("jsonish")).to eq '{"looks": "like json"}'
    expect(reopened.get("obj")).to eq({ "real" => "object" })
    reopened.close
  end
end
