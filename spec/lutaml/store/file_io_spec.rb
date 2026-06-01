# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

class FileTestItem < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :value, :string

  key_value do
    map :name, to: :name
    map :value, to: :value
  end
end

RSpec.describe "Lutaml::Store file I/O" do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.rm_rf(tmpdir) }

  let(:store) do
    Lutaml::Store.new(
      adapter: :memory,
      models: [{ model: FileTestItem, key: :name, dir: "items" }]
    )
  end

  let(:items) do
    [
      FileTestItem.new(name: "alpha", value: "first"),
      FileTestItem.new(name: "beta", value: "second"),
      FileTestItem.new(name: "gamma", value: "third")
    ]
  end

  def items_dir
    File.join(tmpdir, "items")
  end

  # ── YAML format ──

  describe "YAML separate layout" do
    it "round-trips models" do
      store.save_all(items, path: tmpdir, format: :yaml, layout: :separate)

      expect(Dir.glob(File.join(items_dir, "*.{yaml,yml}")).size).to eq(3)

      loaded = store.load_all(FileTestItem, path: tmpdir, format: :yaml, layout: :separate)
      expect(loaded.size).to eq(3)
      expect(loaded.map(&:name).sort).to eq(%w[alpha beta gamma])
      expect(loaded.map(&:value).sort).to eq(%w[first second third])
    end

    it "writes one file per model named by key" do
      store.save_all(items, path: tmpdir, format: :yaml, layout: :separate)

      expect(File.exist?(File.join(items_dir, "alpha.yaml"))).to be true
      expect(File.exist?(File.join(items_dir, "beta.yaml"))).to be true
      expect(File.exist?(File.join(items_dir, "gamma.yaml"))).to be true
    end
  end

  describe "YAML grouped layout" do
    it "writes one file per key" do
      store.save_all(items, path: tmpdir, format: :yaml, layout: :grouped)

      files = Dir.glob(File.join(items_dir, "*.yaml")).sort
      expect(files.size).to eq(3)
    end

    it "round-trips models" do
      store.save_all(items, path: tmpdir, format: :yaml, layout: :grouped)

      loaded = store.load_all(FileTestItem, path: tmpdir, format: :yaml, layout: :grouped)
      expect(loaded.size).to eq(3)
      expect(loaded.map(&:name).sort).to eq(%w[alpha beta gamma])
    end
  end

  # ── JSON format ──

  describe "JSON separate layout" do
    it "round-trips models" do
      store.save_all(items, path: tmpdir, format: :json, layout: :separate)

      expect(Dir.glob(File.join(items_dir, "*.json")).size).to eq(3)

      loaded = store.load_all(FileTestItem, path: tmpdir, format: :json, layout: :separate)
      expect(loaded.size).to eq(3)
      expect(loaded.map(&:name).sort).to eq(%w[alpha beta gamma])
    end

    it "writes valid JSON files" do
      store.save_all(items, path: tmpdir, format: :json, layout: :separate)

      Dir.glob(File.join(items_dir, "*.json")).each do |path|
        expect { JSON.parse(File.read(path, encoding: "utf-8")) }.not_to raise_error
      end
    end
  end

  # ── JSONL format ──

  describe "JSONL export/import" do
    it "exports models to JSONL file" do
      export_path = File.join(tmpdir, "data.jsonl")
      store.export(items, path: export_path, format: :jsonl)

      expect(File.exist?(export_path)).to be true
      lines = File.read(export_path, encoding: "utf-8").lines.reject { |l| l.strip.empty? }
      expect(lines.size).to eq(3)
      lines.each { |line| expect { JSON.parse(line) }.not_to raise_error }
    end

    it "round-trips through JSONL file" do
      export_path = File.join(tmpdir, "data.jsonl")
      store.export(items, path: export_path, format: :jsonl)

      fmt = Lutaml::Store::Format.resolve(:jsonl)
      data = File.read(export_path, encoding: "utf-8")
      loaded = fmt.deserialize_many(data, FileTestItem)

      expect(loaded.size).to eq(3)
      expect(loaded.map(&:name).sort).to eq(%w[alpha beta gamma])
    end
  end

  # ── Marshal format ──

  describe "Marshal separate layout" do
    it "round-trips models" do
      store.save_all(items, path: tmpdir, format: :marshal, layout: :separate)

      expect(Dir.glob(File.join(items_dir, "*.bin")).size).to eq(3)

      loaded = store.load_all(FileTestItem, path: tmpdir, format: :marshal, layout: :separate)
      expect(loaded.size).to eq(3)
      expect(loaded.map(&:name).sort).to eq(%w[alpha beta gamma])
    end
  end

  # ── YAMLS format ──

  describe "YAMLS grouped layout" do
    it "writes multi-document YAML files" do
      # Grouped YAMLS: each group file contains multiple docs
      store.save_all(items, path: tmpdir, format: :yamls, layout: :grouped)

      files = Dir.glob(File.join(items_dir, "*.{yaml,yml}")).sort
      expect(files.size).to eq(3)
    end

    it "round-trips models" do
      store.save_all(items, path: tmpdir, format: :yamls, layout: :grouped)

      loaded = store.load_all(FileTestItem, path: tmpdir, format: :yamls, layout: :grouped)
      expect(loaded.size).to eq(3)
      expect(loaded.map(&:name).sort).to eq(%w[alpha beta gamma])
    end
  end

  # ── Edge cases ──

  describe "empty directory" do
    it "returns empty array from load_all" do
      FileUtils.mkdir_p(items_dir)

      loaded = store.load_all(FileTestItem, path: tmpdir, format: :yaml, layout: :separate)
      expect(loaded).to eq([])
    end
  end

  describe "empty model list" do
    it "returns empty array from save_all" do
      result = store.save_all([], path: tmpdir, format: :yaml, layout: :separate)
      expect(result).to eq([])
    end
  end

  describe "missing directory" do
    it "raises BackendError for load_all" do
      expect do
        store.load_all(FileTestItem, path: "/nonexistent/path", format: :yaml, layout: :separate)
      end.to raise_error(Lutaml::Store::BackendError, /Directory not found/)
    end
  end

  describe "no path provided" do
    it "raises BackendError for save_all without path" do
      items_with_no_dir = [
        FileTestItem.new(name: "x", value: "y")
      ]
      # No dir in registration and no path
      bare_store = Lutaml::Store.new(
        adapter: :memory,
        models: [{ model: FileTestItem, key: :name }]
      )
      expect do
        bare_store.save_all(items_with_no_dir, format: :yaml, layout: :separate)
      end.to raise_error(Lutaml::Store::BackendError, /No directory specified/)
    end
  end

  describe "unknown layout" do
    it "raises ConfigurationError" do
      expect do
        store.save_all(items, path: tmpdir, format: :yaml, layout: :unknown)
      end.to raise_error(Lutaml::Store::ConfigurationError, /Unknown layout/)
    end
  end

  describe "unknown format" do
    it "raises UnsupportedFormatError" do
      expect do
        store.save_all(items, path: tmpdir, format: :csv, layout: :separate)
      end.to raise_error(Lutaml::Store::Format::UnsupportedFormatError)
    end
  end
end
