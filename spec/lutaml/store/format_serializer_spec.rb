# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::FormatSerializer do
  before do
    test_model = Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :name, :string
    end
    stub_const("FmtSerTestModel", test_model)
  end

  let(:model) { FmtSerTestModel.new(id: "m1", name: "Test") }

  describe "with :yaml format" do
    let(:serializer) { described_class.new(:yaml) }

    it "round-trips through serialize/deserialize" do
      data = serializer.serialize(model)
      expect(data).to be_a(Hash)
      expect(data["_class"]).to eq("FmtSerTestModel")
      expect(data["_data"]).to include("id: m1")

      loaded = serializer.deserialize(data, FmtSerTestModel)
      expect(loaded.id).to eq("m1")
      expect(loaded.name).to eq("Test")
    end
  end

  describe "with :json format" do
    let(:serializer) { described_class.new(:json) }

    it "round-trips through serialize/deserialize" do
      data = serializer.serialize(model)
      loaded = serializer.deserialize(data, FmtSerTestModel)
      expect(loaded.id).to eq("m1")
      expect(loaded.name).to eq("Test")
    end
  end

  describe "with :marshal format" do
    let(:serializer) { described_class.new(:marshal) }

    it "round-trips through serialize/deserialize" do
      data = serializer.serialize(model)
      expect(data["_data"]).to be_a(String)

      loaded = serializer.deserialize(data, FmtSerTestModel)
      expect(loaded.id).to eq("m1")
      expect(loaded.name).to eq("Test")
    end
  end

  describe "with :xml format" do
    before do
      xml_model = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        attribute :name, :string

        xml do
          root "item"
          map_attribute "id", to: :id
          map_element "name", to: :name
        end
      end
      stub_const("FmtSerXmlModel", xml_model)
    end

    let(:serializer) { described_class.new(:xml) }
    let(:xml_model) { FmtSerXmlModel.new(id: "x1", name: "XML Test") }

    it "round-trips through serialize/deserialize" do
      data = serializer.serialize(xml_model)
      expect(data["_data"]).to include("<item")

      loaded = serializer.deserialize(data, FmtSerXmlModel)
      expect(loaded.id).to eq("x1")
      expect(loaded.name).to eq("XML Test")
    end
  end

  describe "DatabaseStore integration" do
    let(:serializer) { described_class.new(:json) }

    it "works as a custom serializer for DatabaseStore" do
      store = Lutaml::Store.new(
        adapter: :memory,
        models: [{ model: FmtSerTestModel, key: :id, serializer: serializer }]
      )

      store.save(model)
      loaded = store.fetch(model: FmtSerTestModel, id: "m1")
      expect(loaded.id).to eq("m1")
      expect(loaded.name).to eq("Test")
    end

    it "preserves data through update" do
      store = Lutaml::Store.new(
        adapter: :memory,
        models: [{ model: FmtSerTestModel, key: :id, serializer: serializer }]
      )

      store.save(model)
      store.update(model: FmtSerTestModel, id: "m1", attributes: [
                     { key: :name, value: "Updated" }
                   ])

      loaded = store.fetch(model: FmtSerTestModel, id: "m1")
      expect(loaded.name).to eq("Updated")
    end
  end
end
