# frozen_string_literal: true

require "spec_helper"
require "support/simple_test_model"
require "zip"

RSpec.describe Lutaml::Store::PackageTransport::ZipTransport do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.rm_rf(tmpdir) }

  let(:definition) do
    Lutaml::Store::PackageDefinition.new(
      name: :test, metadata_model: SimpleTestModel, metadata_file: "meta.yaml",
      metadata_key: :id
    ) do |pkg|
      pkg.model(model: SimpleTestModel, dir: "items",
                layout: :separate, key: :id, default_format: :yaml)
      pkg.asset("data.bin", type: :file)
    end
  end

  describe "round-trip through ZIP" do
    it "preserves models, metadata, and assets" do
      store = Lutaml::Store::PackageStore.new(definition)
      store.add_model(SimpleTestModel.new(id: "item-1", name: "First"))
      store.metadata = SimpleTestModel.new(id: "meta", name: "Package")
      store.add_asset("data.bin", "BINARY")

      zip_path = File.join(tmpdir, "test.zip")
      store.save(zip_path, transport: :zip)

      expect(File.exist?(zip_path)).to be true

      # Verify ZIP contents
      Zip::File.open(zip_path) do |zf|
        expect(zf.find_entry("meta.yaml")).not_to be_nil
        expect(zf.find_entry("items/item-1.yaml")).not_to be_nil
        expect(zf.find_entry("data.bin")).not_to be_nil
      end

      # Load from ZIP
      loaded = Lutaml::Store::PackageStore.load(definition, zip_path,
                                                transport: :zip)
      expect(loaded.model_count(SimpleTestModel)).to eq(1)
      expect(loaded.metadata.name).to eq("Package")
      expect(loaded.asset("data.bin")).to eq("BINARY")
    end
  end

  describe "directory → ZIP → directory round-trip" do
    it "preserves data through format conversion" do
      dir = File.join(tmpdir, "source")
      dir_store = Lutaml::Store::PackageStore.new(definition)
      dir_store.add_model(SimpleTestModel.new(id: "abc", name: "Test"))
      dir_store.metadata = SimpleTestModel.new(id: "meta", name: "Dir Package")
      dir_store.save(dir, transport: :directory)

      loaded_from_dir = Lutaml::Store::PackageStore.load(definition, dir,
                                                         transport: :directory)
      zip_path = File.join(tmpdir, "converted.zip")
      loaded_from_dir.save(zip_path, transport: :zip)

      loaded_from_zip = Lutaml::Store::PackageStore.load(definition, zip_path,
                                                         transport: :zip)
      expect(loaded_from_zip.model_count(SimpleTestModel)).to eq(1)
      expect(loaded_from_zip.fetch_model(SimpleTestModel, "abc").name).to eq("Test")
      expect(loaded_from_zip.metadata.name).to eq("Dir Package")
    end
  end

  describe "format override in ZIP" do
    it "writes models in JSON format" do
      store = Lutaml::Store::PackageStore.new(definition)
      store.add_model(SimpleTestModel.new(id: "item-1", name: "First"))

      zip_path = File.join(tmpdir, "json.zip")
      store.save(zip_path, transport: :zip,
                           formats: { SimpleTestModel => :json })

      Zip::File.open(zip_path) do |zf|
        expect(zf.find_entry("items/item-1.json")).not_to be_nil
      end
    end
  end
end
