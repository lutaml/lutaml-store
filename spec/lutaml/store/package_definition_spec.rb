# frozen_string_literal: true

require "spec_helper"
require "support/simple_test_model"
require "support/yamls_test_model"

RSpec.describe Lutaml::Store::PackageDefinition do
  subject(:definition) do
    described_class.new(
      name: :test,
      metadata_model: SimpleTestModel,
      metadata_file: "meta.yaml"
    ) do |pkg|
      pkg.model(model: YamlsTestModel, dir: "items",
                layout: :separate, key: :id, default_format: :yamls)
      pkg.model(model: SimpleTestModel, file: "config.yaml",
                key: :id, default_format: :yaml)
      pkg.asset("images", type: :directory)
      pkg.asset("readme.txt", type: :file)
    end
  end

  it "stores name" do
    expect(definition.name).to eq(:test)
  end

  it "stores metadata model and file" do
    expect(definition.metadata_model).to eq(SimpleTestModel)
    expect(definition.metadata_file).to eq("meta.yaml")
  end

  it "stores model entries" do
    expect(definition.model_entries.length).to eq(2)

    yamls_entry = definition.model_entries.first
    expect(yamls_entry.model).to eq(YamlsTestModel)
    expect(yamls_entry.dir).to eq("items")
    expect(yamls_entry.layout).to eq(:separate)
    expect(yamls_entry.key).to eq(:id)
    expect(yamls_entry.default_format).to eq(:yamls)

    simple_entry = definition.model_entries.last
    expect(simple_entry.model).to eq(SimpleTestModel)
    expect(simple_entry.file).to eq("config.yaml")
  end

  it "stores asset entries" do
    expect(definition.asset_entries.length).to eq(2)
    expect(definition.asset_entries[0].path).to eq("images")
    expect(definition.asset_entries[0].type).to eq(:directory)
    expect(definition.asset_entries[1].path).to eq("readme.txt")
    expect(definition.asset_entries[1].type).to eq(:file)
  end

  describe "dir/file mutual exclusivity" do
    it "raises when both dir and file are specified" do
      expect do
        definition.model(model: SimpleTestModel, dir: "d", file: "f.yaml", key: :id)
      end.to raise_error(ArgumentError, /Specify dir: or file:, not both/)
    end
  end

  describe "#entry_for" do
    it "finds entry by model class" do
      entry = definition.entry_for(YamlsTestModel)
      expect(entry).not_to be_nil
      expect(entry.dir).to eq("items")
    end

    it "returns nil for unknown model" do
      expect(definition.entry_for(String)).to be_nil
    end
  end

  describe "#model_classes" do
    it "returns registered model classes" do
      expect(definition.model_classes).to contain_exactly(YamlsTestModel, SimpleTestModel)
    end
  end

  describe "#database_store_models" do
    it "includes model entries only (metadata is stored separately)" do
      configs = definition.database_store_models
      expect(configs.length).to eq(2) # 2 model entries, no metadata
      models = configs.map { |c| c[:model] }
      expect(models).to contain_exactly(YamlsTestModel, SimpleTestModel)
    end
  end
end
