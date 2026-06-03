# frozen_string_literal: true

require "spec_helper"
require "support/simple_test_model"
require "support/yamls_test_model"

RSpec.describe Lutaml::Store::PackageStore do
  let(:definition) do
    Lutaml::Store::PackageDefinition.new(name: :test) do |pkg|
      pkg.model(model: SimpleTestModel, dir: "items",
                layout: :separate, key: :id, default_format: :yaml)
    end
  end

  let(:store) { described_class.new(definition) }

  describe "#add_model / #models_for" do
    it "stores and retrieves model instances" do
      model = SimpleTestModel.new(id: "test-1", name: "Test")
      store.add_model(model)
      expect(store.models_for(SimpleTestModel)).to include(model)
    end

    it "stores multiple instances" do
      3.times { |i| store.add_model(SimpleTestModel.new(id: "test-#{i}")) }
      expect(store.model_count(SimpleTestModel)).to eq(3)
    end
  end

  describe "#fetch_model" do
    it "retrieves by key" do
      model = SimpleTestModel.new(id: "abc", name: "ABC")
      store.add_model(model)
      expect(store.fetch_model(SimpleTestModel, "abc").name).to eq("ABC")
    end

    it "returns nil for missing key" do
      expect(store.fetch_model(SimpleTestModel, "missing")).to be_nil
    end
  end

  describe "#model_exists?" do
    it "returns true for existing key" do
      store.add_model(SimpleTestModel.new(id: "exists"))
      expect(store.model_exists?(SimpleTestModel, "exists")).to be true
    end

    it "returns false for missing key" do
      expect(store.model_exists?(SimpleTestModel, "missing")).to be false
    end
  end

  describe "#remove_model" do
    it "removes by key" do
      store.add_model(SimpleTestModel.new(id: "remove-me"))
      store.remove_model(SimpleTestModel, "remove-me")
      expect(store.model_exists?(SimpleTestModel, "remove-me")).to be false
    end
  end

  describe "#metadata=" do
    let(:def_with_metadata) do
      Lutaml::Store::PackageDefinition.new(
        name: :test, metadata_model: SimpleTestModel,
        metadata_file: "meta.yaml", metadata_key: :id
      ) do |pkg|
        pkg.model(model: SimpleTestModel, dir: "items",
                  layout: :separate, key: :id, default_format: :yaml)
      end
    end

    it "stores metadata" do
      store = described_class.new(def_with_metadata)
      store.metadata = SimpleTestModel.new(id: "meta", name: "Metadata")
      expect(store.metadata.name).to eq("Metadata")
    end
  end

  describe "#add_asset / #asset" do
    it "stores and retrieves raw content" do
      store.add_asset("images/logo.png", "PNG_DATA")
      expect(store.asset("images/logo.png")).to eq("PNG_DATA")
    end

    it "lists asset paths" do
      store.add_asset("a.txt", "A")
      store.add_asset("b.txt", "B")
      expect(store.asset_paths).to contain_exactly("a.txt", "b.txt")
    end
  end

  describe "#remove_asset" do
    it "removes an asset" do
      store.add_asset("remove.txt", "data")
      store.remove_asset("remove.txt")
      expect(store.asset("remove.txt")).to be_nil
    end
  end

  describe "#clear_all" do
    it "removes everything" do
      store.add_model(SimpleTestModel.new(id: "x"))
      store.add_asset("file.txt", "data")
      store.clear_all
      expect(store.model_count(SimpleTestModel)).to eq(0)
      expect(store.asset_paths).to be_empty
    end
  end

  describe "#stats" do
    it "reports model counts and asset count" do
      store.add_model(SimpleTestModel.new(id: "1"))
      store.add_asset("f.txt", "x")
      stats = store.stats
      expect(stats[:package]).to eq(:test)
      expect(stats[:models][SimpleTestModel.name]).to eq(1)
      expect(stats[:assets]).to eq(1)
    end
  end

  describe "#resolve_formats" do
    let(:def_with_two) do
      Lutaml::Store::PackageDefinition.new(name: :test) do |pkg|
        pkg.model(model: SimpleTestModel, dir: "a", key: :id, default_format: :yaml)
        pkg.model(model: SimpleTestModel, dir: "b", key: :id, default_format: :yamls)
      end
    end

    let(:two_model_store) { described_class.new(def_with_two) }

    it "global format overrides all models" do
      formats = two_model_store.send(:resolve_formats, :json, {})
      expect(formats[SimpleTestModel]).to eq(:json)
    end

    it "per-model format overrides specific models" do
      formats = two_model_store.send(:resolve_formats, nil,
                                     { SimpleTestModel => :marshal })
      expect(formats[SimpleTestModel]).to eq(:marshal)
    end

    it "both: global + per-model merge" do
      formats = two_model_store.send(:resolve_formats, :json,
                                     { SimpleTestModel => :marshal })
      expect(formats[SimpleTestModel]).to eq(:marshal)
    end

    it "nil: use defaults (empty hash)" do
      formats = two_model_store.send(:resolve_formats, nil, {})
      expect(formats).to be_empty
    end
  end
end
