# frozen_string_literal: true

require "spec_helper"
require "support/simple_test_model"

RSpec.describe Lutaml::Store::PackageTransport::DirectoryTransport do
  let(:transport) { described_class.new }
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.rm_rf(tmpdir) }

  let(:definition) do
    Lutaml::Store::PackageDefinition.new(
      name: :test, metadata_model: SimpleTestModel,
      metadata_file: "meta.yaml", metadata_key: :id
    ) do |pkg|
      pkg.model(model: SimpleTestModel, dir: "items",
                layout: :separate, key: :id, default_format: :yaml)
      pkg.asset("data.bin", type: :file)
      pkg.asset("images", type: :directory)
    end
  end

  describe "round-trip: write then read" do
    it "preserves models, metadata, and assets" do
      store = Lutaml::Store::PackageStore.new(definition)
      store.add_model(SimpleTestModel.new(id: "item-1", name: "First"))
      store.add_model(SimpleTestModel.new(id: "item-2", name: "Second"))
      store.metadata = SimpleTestModel.new(id: "meta", name: "Test Package")
      store.add_asset("data.bin", "BINARY_CONTENT")
      store.add_asset("images/logo.png", "PNG_BYTES")

      output_dir = File.join(tmpdir, "output")
      store.save(output_dir, transport: :directory)

      # Verify file structure
      expect(File.exist?(File.join(output_dir, "meta.yaml"))).to be true
      expect(File.exist?(File.join(output_dir, "items", "item-1.yaml"))).to be true
      expect(File.exist?(File.join(output_dir, "items", "item-2.yaml"))).to be true
      expect(File.exist?(File.join(output_dir, "data.bin"))).to be true
      expect(File.exist?(File.join(output_dir, "images", "logo.png"))).to be true

      # Load back
      loaded = Lutaml::Store::PackageStore.load(definition, output_dir,
                                                transport: :directory)
      expect(loaded.model_count(SimpleTestModel)).to eq(2)
      expect(loaded.metadata.name).to eq("Test Package")
      expect(loaded.asset("data.bin")).to eq("BINARY_CONTENT")
      expect(loaded.asset("images/logo.png")).to eq("PNG_BYTES")
    end
  end

  describe "missing optional entries" do
    it "loads successfully with empty directory" do
      empty_dir = File.join(tmpdir, "empty")
      FileUtils.mkdir_p(File.join(empty_dir, "items"))
      loaded = Lutaml::Store::PackageStore.load(definition, empty_dir,
                                                transport: :directory)
      expect(loaded.model_count(SimpleTestModel)).to eq(0)
      expect(loaded.metadata).to be_nil
    end
  end

  describe "format override" do
    it "writes models in JSON format when overridden" do
      store = Lutaml::Store::PackageStore.new(definition)
      store.add_model(SimpleTestModel.new(id: "item-1", name: "First"))

      output_dir = File.join(tmpdir, "json")
      store.save(output_dir, transport: :directory,
                             formats: { SimpleTestModel => :json })

      files = Dir.glob(File.join(output_dir, "items", "*"))
      expect(files.length).to eq(1)
      expect(File.extname(files.first)).to eq(".json")
    end

    it "loads models saved in JSON format" do
      store = Lutaml::Store::PackageStore.new(definition)
      store.add_model(SimpleTestModel.new(id: "item-1", name: "First"))

      output_dir = File.join(tmpdir, "json")
      store.save(output_dir, transport: :directory,
                             formats: { SimpleTestModel => :json })

      loaded = Lutaml::Store::PackageStore.load(definition, output_dir,
                                                transport: :directory,
                                                format: :json)
      expect(loaded.model_count(SimpleTestModel)).to eq(1)
      expect(loaded.fetch_model(SimpleTestModel, "item-1").name).to eq("First")
    end
  end

  describe "corrupt file handling" do
    it "warns and continues when a model file is corrupt" do
      dir = File.join(tmpdir, "corrupt")
      FileUtils.mkdir_p(File.join(dir, "items"))
      File.write(File.join(dir, "items", "good.yaml"), "---\nid: good\nname: OK\n")
      File.write(File.join(dir, "items", "bad.yaml"), "{{{{not yaml")

      expect do
        Lutaml::Store::PackageStore.load(definition, dir, transport: :directory)
      end.to output(/failed to load/).to_stderr

      loaded = Lutaml::Store::PackageStore.load(definition, dir,
                                                transport: :directory)
      expect(loaded.model_count(SimpleTestModel)).to eq(1)
    end
  end

  describe "dir: nil (root-level models)" do
    let(:root_definition) do
      Lutaml::Store::PackageDefinition.new(name: :root_test) do |pkg|
        pkg.model(model: SimpleTestModel, dir: nil,
                  layout: :separate, key: :id, default_format: :yaml)
      end
    end

    it "writes models to package root" do
      store = Lutaml::Store::PackageStore.new(root_definition)
      store.add_model(SimpleTestModel.new(id: "root-1", name: "Root"))

      output_dir = File.join(tmpdir, "root")
      store.save(output_dir, transport: :directory)

      expect(File.exist?(File.join(output_dir, "root-1.yaml"))).to be true
    end

    it "reads models from package root" do
      dir = File.join(tmpdir, "root_read")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "abc.yaml"), "---\nid: abc\nname: Found\n")

      loaded = Lutaml::Store::PackageStore.load(root_definition, dir,
                                                transport: :directory)
      expect(loaded.model_count(SimpleTestModel)).to eq(1)
      expect(loaded.fetch_model(SimpleTestModel, "abc").name).to eq("Found")
    end
  end
end
