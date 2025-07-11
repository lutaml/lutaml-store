# frozen_string_literal: true

require "spec_helper"

# Load the fake Lutaml::Model::Serializable from the integration spec
require_relative "lutaml_model_integration_spec"

# Mock Lutaml::Model class for testing that inherits from Lutaml::Model::Serializable
class MockModel < Lutaml::Model::Serializable
  def initialize(id: nil, name: nil, data: nil)
    super(
      id: id,
      name: name,
      data: data
    )
  end

  def self.from_hash(hash)
    # Convert string keys to symbols for consistency
    symbolized_hash = {}
    hash.each do |key, value|
      symbolized_hash[key.to_sym] = value
    end
    new(
      id: symbolized_hash[:id],
      name: symbolized_hash[:name],
      data: symbolized_hash[:data]
    )
  end

  def ==(other)
    other.is_a?(MockModel) &&
      id == other.id &&
      name == other.name &&
      normalize_data(data) == normalize_data(other.data)
  end

  private

  def normalize_data(data)
    return data unless data.is_a?(Hash)

    data.transform_keys(&:to_s)
  end
end

RSpec.describe Lutaml::Store::ModelStore do
  let(:config) { { "backend" => { "type" => "memory" } } }
  let(:model_class) { MockModel }
  let(:format) { :marshal }
  let(:store) { described_class.new(config, model_class: model_class, format: format) }

  let(:sample_model) { MockModel.new(id: 1, name: "Test", data: { key: "value" }) }
  let(:another_model) { MockModel.new(id: 2, name: "Another", data: { foo: "bar" }) }

  describe "#initialize" do
    it "creates a model store with default format" do
      store = described_class.new(config, model_class: model_class)
      expect(store.format).to eq(:marshal)
      expect(store.model_class).to eq(model_class)
    end

    it "creates a model store with specified format" do
      store = described_class.new(config, model_class: model_class, format: :json)
      expect(store.format).to eq(:json)
    end

    it "raises error for unsupported format" do
      expect {
        described_class.new(config, model_class: model_class, format: :invalid)
      }.to raise_error(Lutaml::Store::ConfigurationError)
    end
  end

  describe "#store_model and #get_model" do
    it "stores and retrieves a model" do
      store.store_model("test_key", sample_model)
      retrieved = store.get_model("test_key")

      expect(retrieved).to eq(sample_model)
    end

    it "returns nil for non-existent keys" do
      expect(store.get_model("non_existent")).to be_nil
    end

    it "validates model type when model_class is set" do
      expect {
        store.store_model("key", "not a model")
      }.to raise_error(ArgumentError, /Expected MockModel/)
    end
  end

  describe "different serialization formats" do
    context "with JSON format" do
      let(:format) { :json }

      it "stores and retrieves models using JSON" do
        store.store_model("json_key", sample_model)
        retrieved = store.get_model("json_key")

        expect(retrieved).to eq(sample_model)
      end
    end

    context "with YAML format" do
      let(:format) { :yaml }

      it "stores and retrieves models using YAML" do
        store.store_model("yaml_key", sample_model)
        retrieved = store.get_model("yaml_key")

        expect(retrieved).to eq(sample_model)
      end
    end

    context "with hash format" do
      let(:format) { :hash }

      it "stores and retrieves models using hash" do
        store.store_model("hash_key", sample_model)
        retrieved = store.get_model("hash_key")

        expect(retrieved).to eq(sample_model)
      end
    end
  end

  describe "#store_models" do
    it "stores multiple models with default key generator" do
      models = [sample_model, another_model]
      store.store_models(models)

      expect(store.model_count).to eq(2)
      expect(store.model_keys).to include("mockmodel_0", "mockmodel_1")
    end

    it "stores multiple models with custom key generator" do
      models = [sample_model, another_model]
      key_gen = ->(model, _) { "model_#{model.id}" }

      store.store_models(models, key_gen)

      expect(store.get_model("model_1")).to eq(sample_model)
      expect(store.get_model("model_2")).to eq(another_model)
    end
  end

  describe "#all_models" do
    it "returns all stored models" do
      store.store_model("key1", sample_model)
      store.store_model("key2", another_model)

      all = store.all_models
      expect(all.size).to eq(2)
      expect(all["key1"]).to eq(sample_model)
      expect(all["key2"]).to eq(another_model)
    end
  end

  describe "#find_models" do
    before do
      store.store_model("key1", sample_model)
      store.store_model("key2", another_model)
    end

    it "finds models by criteria" do
      found = store.find_models { |key, model| model.id == 1 }
      expect(found.size).to eq(1)
      expect(found["key1"]).to eq(sample_model)
    end

    it "returns enumerator when no block given" do
      enum = store.find_models
      expect(enum).to be_a(Enumerator)
    end
  end

  describe "#update_model" do
    it "updates an existing model" do
      store.store_model("key1", sample_model)

      updated = store.update_model("key1") do |model|
        model.name = "Updated Name"
        model
      end

      expect(updated.name).to eq("Updated Name")
      expect(store.get_model("key1").name).to eq("Updated Name")
    end

    it "returns nil for non-existent key" do
      result = store.update_model("non_existent") { |model| model }
      expect(result).to be_nil
    end
  end

  describe "#delete_model" do
    it "deletes an existing model" do
      store.store_model("key1", sample_model)
      expect(store.model_exists?("key1")).to be true

      result = store.delete_model("key1")
      expect(result).to be true
      expect(store.model_exists?("key1")).to be false
    end

    it "returns false for non-existent key" do
      result = store.delete_model("non_existent")
      expect(result).to be false
    end
  end

  describe "bulk operations" do
    let(:models_hash) { { "key1" => sample_model, "key2" => another_model } }

    describe "#bulk_store" do
      it "stores multiple key-model pairs" do
        store.bulk_store(models_hash)

        expect(store.model_count).to eq(2)
        expect(store.get_model("key1")).to eq(sample_model)
        expect(store.get_model("key2")).to eq(another_model)
      end
    end

    describe "#bulk_get" do
      it "retrieves multiple models by keys" do
        store.bulk_store(models_hash)

        result = store.bulk_get(["key1", "key2", "non_existent"])
        expect(result["key1"]).to eq(sample_model)
        expect(result["key2"]).to eq(another_model)
        expect(result["non_existent"]).to be_nil
      end
    end

    describe "#bulk_delete" do
      it "deletes multiple models by keys" do
        store.bulk_store(models_hash)

        result = store.bulk_delete(["key1", "key2"])
        expect(result["key1"]).to be true
        expect(result["key2"]).to be true
        expect(store.model_count).to eq(0)
      end
    end
  end

  describe "#export_models and #import_models" do
    before do
      store.store_model("key1", sample_model)
      store.store_model("key2", another_model)
    end

    it "exports models to different format" do
      exported = {}
      store.export_models(:json) do |key, serialized|
        exported[key] = serialized
      end

      expect(exported.size).to eq(2)
      expect(exported["key1"]).to be_a(String)

      parsed = JSON.parse(exported["key1"])
      # With polymorphic support, data is wrapped with type information
      if parsed.key?("_data")
        expect(parsed["_type"]).to eq("MockModel")
        expect(parsed["_data"]).to include("id" => 1)
      else
        # Fallback for non-polymorphic serialization
        expect(parsed).to include("id" => 1)
      end
    end

    it "imports models from different format" do
      # Export to JSON first
      exported = {}
      store.export_models(:json) { |key, data| exported[key] = data }

      # Clear and import back
      store.clear_models
      expect(store.model_count).to eq(0)

      store.import_models(exported, :json)
      expect(store.model_count).to eq(2)
      expect(store.get_model("key1")).to eq(sample_model)
    end
  end

  describe "#stats" do
    it "includes model-specific statistics" do
      store.store_model("key1", sample_model)

      stats = store.stats
      expect(stats[:model_class]).to eq("MockModel")
      expect(stats[:format]).to eq(format)
      expect(stats[:model_count]).to eq(1)
    end
  end

  describe "event handling" do
    it "emits events for model operations" do
      events = []
      store.on(:store_model) { |data| events << [:store_model, data] }
      store.on(:get_model) { |data| events << [:get_model, data] }
      store.on(:delete_model) { |data| events << [:delete_model, data] }

      store.store_model("key1", sample_model)
      store.get_model("key1")
      store.delete_model("key1")

      expect(events.size).to eq(3)
      expect(events[0][0]).to eq(:store_model)
      expect(events[1][0]).to eq(:get_model)
      expect(events[2][0]).to eq(:delete_model)
    end
  end

  describe "#close" do
    it "closes the underlying store" do
      expect(store.store).to receive(:close)
      store.close
    end
  end
end
