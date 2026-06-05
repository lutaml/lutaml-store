# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::Format::Xml do
  let(:fmt) { Lutaml::Store::Format.resolve(:xml) }

  before do
    xml_class = Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :name, :string

      xml do
        root "item"
        map_attribute "id", to: :id
        map_element "name", to: :name
      end
    end
    stub_const("XmlTestModel", xml_class)
  end

  let(:model) { XmlTestModel.new(id: "x1", name: "Test Item") }

  describe "format metadata" do
    it "has .xml extension" do
      expect(fmt.extension).to eq(".xml")
    end

    it "has *.xml glob pattern" do
      expect(fmt.glob_pattern).to eq("*.xml")
    end

    it "is not binary" do
      expect(fmt.binary?).to be false
    end
  end

  describe "#serialize / #deserialize" do
    it "round-trips a single model" do
      xml = fmt.serialize(model)
      loaded = fmt.deserialize(xml, XmlTestModel)
      expect(loaded.id).to eq("x1")
      expect(loaded.name).to eq("Test Item")
    end
  end

  describe "#serialize_many / #deserialize_many" do
    let(:models) do
      [
        XmlTestModel.new(id: "x1", name: "First"),
        XmlTestModel.new(id: "x2", name: "Second"),
        XmlTestModel.new(id: "x3", name: "Third")
      ]
    end

    it "round-trips multiple models" do
      xml = fmt.serialize_many(models)
      loaded = fmt.deserialize_many(xml, XmlTestModel)
      expect(loaded.size).to eq(3)
      expect(loaded.map(&:id)).to eq(%w[x1 x2 x3])
      expect(loaded.map(&:name)).to eq(%w[First Second Third])
    end

    it "wraps in <items> root element" do
      xml = fmt.serialize_many(models)
      expect(xml).to start_with("<items>")
      expect(xml).to end_with("</items>")
    end
  end

  describe "PackageStore integration" do
    let(:definition) do
      Lutaml::Store::PackageDefinition.new(
        name: "xml_test",
        metadata_model: nil,
        metadata_file: nil
      ) do |pkg|
        pkg.model(model: XmlTestModel, key: :id, dir: "items", default_format: :xml)
      end
    end

    it "round-trips through directory transport" do
      Dir.mktmpdir do |tmpdir|
        store = Lutaml::Store::PackageStore.new(definition)
        3.times { |i| store.add_model(XmlTestModel.new(id: "x#{i}", name: "Item #{i}")) }
        store.save(tmpdir)

        loaded = Lutaml::Store::PackageStore.load(definition, tmpdir)
        expect(loaded.model_count(XmlTestModel)).to eq(3)
        expect(loaded.fetch_model(XmlTestModel, "x1").name).to eq("Item 1")
      end
    end

    it "round-trips through ZIP transport" do
      Dir.mktmpdir do |tmpdir|
        store = Lutaml::Store::PackageStore.new(definition)
        3.times { |i| store.add_model(XmlTestModel.new(id: "x#{i}", name: "Item #{i}")) }

        zip_path = File.join(tmpdir, "test.zip")
        store.save(zip_path, transport: :zip)

        loaded = Lutaml::Store::PackageStore.load(definition, zip_path, transport: :zip)
        expect(loaded.model_count(XmlTestModel)).to eq(3)
        expect(loaded.fetch_model(XmlTestModel, "x0").name).to eq("Item 0")
      end
    end
  end
end
