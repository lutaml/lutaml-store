# frozen_string_literal: true

require "spec_helper"

module DatabaseStoreTestModels
  class TestStudio < Lutaml::Model::Serializable
    attribute :studio_key, :string
    attribute :name, :string
    attribute :location, :string
    attribute :_class, :string, default: -> { "TestStudio" }, polymorphic_class: true
  end

  class TestCeramicStudio < TestStudio
    attribute :clay_type, :string
    attribute :_class, :string, default: -> { "TestCeramicStudio" }
  end

  class TestPotteryClass < Lutaml::Model::Serializable
    attribute :class_id, :string
    attribute :description, :string
    attribute :studio, TestStudio, polymorphic: true
  end
end

RSpec.describe Lutaml::Store::DatabaseStore do
  let(:config) { { adapter_type: :memory } }

  let(:models) do
    [
      { model: DatabaseStoreTestModels::TestPotteryClass, key: :class_id },
      { model: DatabaseStoreTestModels::TestStudio, key: :studio_key, polymorphic_class_key: :_class },
      { model: DatabaseStoreTestModels::TestCeramicStudio, key: :studio_key, polymorphic_class_key: :_class }
    ]
  end

  let(:store) { described_class.new(adapter: :memory, models: models) }

  describe "#initialize" do
    it "creates a database store with models" do
      expect(store).to be_a(described_class)
      expect(store.registry.count).to eq(3)
    end

    it "raises error when no models provided" do
      expect do
        described_class.new(adapter: :memory, models: [])
      end.to raise_error(Lutaml::Store::ConfigurationError, /No models registered/)
    end
  end

  describe "#save and #fetch" do
    let(:studio) { DatabaseStoreTestModels::TestStudio.new(studio_key: "test_studio", name: "Test Studio") }
    let(:pottery_class) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_101",
        description: "Basic pottery",
        studio: studio
      )
    end

    it "saves and fetches a model with composite relationships" do
      store.save(pottery_class)

      fetched = store.fetch(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "pottery_101")
      expect(fetched).to be_a(DatabaseStoreTestModels::TestPotteryClass)
      expect(fetched.class_id).to eq("pottery_101")
      expect(fetched.description).to eq("Basic pottery")
      expect(fetched.studio).to be_a(DatabaseStoreTestModels::TestStudio)
      expect(fetched.studio.studio_key).to eq("test_studio")
      expect(fetched.studio.name).to eq("Test Studio")
    end

    it "handles polymorphic models correctly" do
      ceramic_studio = DatabaseStoreTestModels::TestCeramicStudio.new(
        studio_key: "ceramic_studio",
        name: "Ceramic Studio",
        clay_type: "Porcelain"
      )

      store.save(ceramic_studio)

      fetched = store.fetch(model: DatabaseStoreTestModels::TestStudio, studio_key: "ceramic_studio")
      expect(fetched).to be_a(DatabaseStoreTestModels::TestCeramicStudio)
      expect(fetched.clay_type).to eq("Porcelain")
    end

    it "returns nil for non-existent models" do
      result = store.fetch(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "nonexistent")
      expect(result).to be_nil
    end
  end

  describe "#update" do
    let(:studio) { DatabaseStoreTestModels::TestStudio.new(studio_key: "test_studio", name: "Test Studio") }
    let(:pottery_class) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_101",
        description: "Basic pottery",
        studio: studio
      )
    end

    before { store.save(pottery_class) }

    it "updates with block" do
      updated = store.update(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "pottery_101") do |model|
        model.description = "Advanced pottery"
        model
      end

      expect(updated.description).to eq("Advanced pottery")

      fetched = store.fetch(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "pottery_101")
      expect(fetched.description).to eq("Advanced pottery")
    end

    it "updates with hash including dot notation" do
      updated = store.update(
        model: DatabaseStoreTestModels::TestPotteryClass,
        class_id: "pottery_101",
        attributes: { "studio.location" => "Downtown" }
      )

      expect(updated.studio.location).to eq("Downtown")

      fetched = store.fetch(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "pottery_101")
      expect(fetched.studio.location).to eq("Downtown")
    end
  end

  describe "#destroy" do
    let(:studio) { DatabaseStoreTestModels::TestStudio.new(studio_key: "test_studio", name: "Test Studio") }
    let(:pottery_class) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_101",
        description: "Basic pottery",
        studio: studio
      )
    end

    before { store.save(pottery_class) }

    it "destroys a model and its composite relationships" do
      result = store.destroy(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "pottery_101")
      expect(result).to be true

      fetched = store.fetch(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "pottery_101")
      expect(fetched).to be_nil

      studio_fetched = store.fetch(model: DatabaseStoreTestModels::TestStudio, studio_key: "test_studio")
      expect(studio_fetched).to be_nil
    end

    it "returns false for non-existent models" do
      result = store.destroy(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "nonexistent")
      expect(result).to be false
    end
  end

  describe "#where" do
    let(:studio1) { DatabaseStoreTestModels::TestStudio.new(studio_key: "studio1", name: "Studio One") }
    let(:studio2) { DatabaseStoreTestModels::TestStudio.new(studio_key: "studio2", name: "Studio Two") }
    let(:pottery1) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_101",
        description: "Basic pottery",
        studio: studio1
      )
    end
    let(:pottery2) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_201",
        description: "Advanced pottery",
        studio: studio2
      )
    end

    before do
      store.save([pottery1, pottery2])
    end

    it "finds models by criteria" do
      results = store.where(model: DatabaseStoreTestModels::TestPotteryClass, description: "Basic pottery")
      expect(results.size).to eq(1)
      expect(results.first.class_id).to eq("pottery_101")
    end
  end

  describe "#all" do
    let(:studio1) { DatabaseStoreTestModels::TestStudio.new(studio_key: "studio1", name: "Studio One") }
    let(:studio2) { DatabaseStoreTestModels::TestStudio.new(studio_key: "studio2", name: "Studio Two") }
    let(:pottery1) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_101",
        description: "Basic pottery",
        studio: studio1
      )
    end
    let(:pottery2) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_201",
        description: "Advanced pottery",
        studio: studio2
      )
    end

    before do
      store.save([pottery1, pottery2])
    end

    it "returns all models of a specific type" do
      results = store.all(model: DatabaseStoreTestModels::TestPotteryClass)
      expect(results.size).to eq(2)
      expect(results.map(&:class_id)).to contain_exactly("pottery_101", "pottery_201")
    end
  end

  describe "#exists?" do
    let(:studio) { DatabaseStoreTestModels::TestStudio.new(studio_key: "test_studio", name: "Test Studio") }
    let(:pottery_class) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_101",
        description: "Basic pottery",
        studio: studio
      )
    end

    before { store.save(pottery_class) }

    it "returns true for existing models" do
      expect(store.exists?(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "pottery_101")).to be true
    end

    it "returns false for non-existent models" do
      expect(store.exists?(model: DatabaseStoreTestModels::TestPotteryClass, class_id: "nonexistent")).to be false
    end
  end

  describe "#count" do
    let(:studio1) { DatabaseStoreTestModels::TestStudio.new(studio_key: "studio1", name: "Studio One") }
    let(:studio2) { DatabaseStoreTestModels::TestStudio.new(studio_key: "studio2", name: "Studio Two") }
    let(:pottery1) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_101",
        description: "Basic pottery",
        studio: studio1
      )
    end
    let(:pottery2) do
      DatabaseStoreTestModels::TestPotteryClass.new(
        class_id: "pottery_201",
        description: "Advanced pottery",
        studio: studio2
      )
    end

    before do
      store.save([pottery1, pottery2])
    end

    it "returns count of models" do
      expect(store.count(model: DatabaseStoreTestModels::TestPotteryClass)).to eq(2)
      expect(store.count(model: DatabaseStoreTestModels::TestStudio)).to eq(2)
    end
  end

  describe "#stats" do
    it "provides statistics" do
      stats = store.stats
      expect(stats).to include(:models_registered, :registered_models, :total_models)
      expect(stats[:models_registered]).to eq(3)
      expect(stats[:registered_models]).to include(
        "DatabaseStoreTestModels::TestPotteryClass",
        "DatabaseStoreTestModels::TestStudio",
        "DatabaseStoreTestModels::TestCeramicStudio"
      )
    end
  end
end
