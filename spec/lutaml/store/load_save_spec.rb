# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Test model using lutaml-model
class TestItem < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :value, :string

  key_value do
    map :name, to: :name
    map :value, to: :value
  end
end

RSpec.describe "Lutaml::Store load_all / save_all" do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.rm_rf(tmpdir) }

  let(:store) do
    Lutaml::Store.new(
      adapter: :memory,
      models: [{ model: TestItem, key: :name, dir: "items" }]
    )
  end

  let(:items) do
    [
      TestItem.new(name: "alpha", value: "first"),
      TestItem.new(name: "beta", value: "second"),
      TestItem.new(name: "gamma", value: "third")
    ]
  end

  describe "#save_all with :yaml format" do
    it "writes YAML files to the model directory" do
      store.save_all(items, path: tmpdir, format: :yaml, layout: :separate)

      items_dir = File.join(tmpdir, "items")
      expect(Dir.exist?(items_dir)).to be true

      files = Dir.glob(File.join(items_dir, "*.yaml")).sort
      expect(files.size).to eq(3)

      content = File.read(files.first, encoding: "utf-8")
      expect(content).to include("name:")
      expect(content).to include("value:")
    end
  end

  describe "#load_all with :yaml format" do
    it "round-trips models through YAML files" do
      store.save_all(items, path: tmpdir, format: :yaml, layout: :separate)

      loaded = store.load_all(TestItem, path: tmpdir, format: :yaml, layout: :separate)

      expect(loaded.size).to eq(3)
      names = loaded.map(&:name).sort
      expect(names).to eq(%w[alpha beta gamma])
      values = loaded.map(&:value).sort
      expect(values).to eq(%w[first second third])
    end
  end

  describe "#save_all with :grouped layout" do
    it "writes one file per key" do
      store.save_all(items, path: tmpdir, format: :yaml, layout: :grouped)

      items_dir = File.join(tmpdir, "items")
      files = Dir.glob(File.join(items_dir, "*.yaml")).sort
      expect(files.size).to eq(3)
    end
  end

  describe "#save_all with :json format" do
    it "writes JSON files" do
      store.save_all(items, path: tmpdir, format: :json, layout: :separate)

      items_dir = File.join(tmpdir, "items")
      files = Dir.glob(File.join(items_dir, "*.json")).sort
      expect(files.size).to eq(3)

      content = File.read(files.first, encoding: "utf-8")
      expect(content).to include('"name"')
    end
  end

  describe "#export" do
    it "exports all models to a single file" do
      export_path = File.join(tmpdir, "export.jsonl")
      store.export(items, path: export_path, format: :jsonl)

      expect(File.exist?(export_path)).to be true
      content = File.read(export_path, encoding: "utf-8")
      lines = content.lines.reject(&:empty?)
      expect(lines.size).to eq(3)
    end
  end

  describe "empty model list" do
    it "returns empty array for save_all" do
      result = store.save_all([], path: tmpdir, format: :yaml, layout: :separate)
      expect(result).to eq([])
    end
  end
end
