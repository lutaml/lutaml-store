# frozen_string_literal: true

require "spec_helper"

module QueryTestModels
  class Item < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :name, :string
    attribute :status, :string
    attribute :year, :integer
    attribute :score, :float

    key_value do
      map :id, to: :id
      map :name, to: :name
      map :status, to: :status
      map :year, to: :year
      map :score, to: :score
    end
  end
end

RSpec.describe Lutaml::Store::Query do
  let(:store) do
    Lutaml::Store.new(
      adapter: :memory,
      models: [{ model: QueryTestModels::Item, key: :id }]
    )
  end

  let(:items) do
    [
      QueryTestModels::Item.new(id: "1", name: "Alpha", status: "published", year: 2020, score: 85.0),
      QueryTestModels::Item.new(id: "2", name: "Beta", status: "draft", year: 2021, score: 92.5),
      QueryTestModels::Item.new(id: "3", name: "Gamma", status: "published", year: 2023, score: 78.0),
      QueryTestModels::Item.new(id: "4", name: "Delta", status: "archived", year: 2019, score: 95.0),
      QueryTestModels::Item.new(id: "5", name: "Epsilon", status: "published", year: 2024, score: 88.0)
    ]
  end

  before do
    items.each { |item| store.save(item) }
  end

  describe "#where" do
    it "filters by equality" do
      results = store.query(QueryTestModels::Item).where(status: "published").to_a
      expect(results.size).to eq(3)
      expect(results.map(&:name)).to contain_exactly("Alpha", "Gamma", "Epsilon")
    end

    it "filters by range" do
      results = store.query(QueryTestModels::Item).where(year: 2020..2023).to_a
      expect(results.size).to eq(3)
      expect(results.map(&:name)).to contain_exactly("Alpha", "Beta", "Gamma")
    end

    it "filters by inclusion" do
      results = store.query(QueryTestModels::Item).where(status: %w[draft archived]).to_a
      expect(results.size).to eq(2)
      expect(results.map(&:name)).to contain_exactly("Beta", "Delta")
    end

    it "chains multiple where clauses (AND)" do
      results = store.query(QueryTestModels::Item)
                     .where(status: "published")
                     .where(year: 2023..2024)
                     .to_a
      expect(results.size).to eq(2)
      expect(results.map(&:name)).to contain_exactly("Gamma", "Epsilon")
    end

    it "accepts explicit Predicate objects" do
      results = store.query(QueryTestModels::Item)
                     .where(Lutaml::Store::Predicate.gt(:year, 2021))
                     .to_a
      expect(results.size).to eq(2)
      expect(results.map(&:name)).to contain_exactly("Gamma", "Epsilon")
    end

    it "returns empty array for no matches" do
      results = store.query(QueryTestModels::Item).where(status: "nonexistent").to_a
      expect(results).to be_empty
    end
  end

  describe "#not" do
    it "negates conditions" do
      results = store.query(QueryTestModels::Item)
                     .where(status: "published")
                     .not(year: 2020..2022)
                     .to_a
      expect(results.size).to eq(2)
      expect(results.map(&:name)).to contain_exactly("Gamma", "Epsilon")
    end

    it "negates equality" do
      results = store.query(QueryTestModels::Item)
                     .not(status: "published")
                     .to_a
      expect(results.size).to eq(2)
      expect(results.map(&:name)).to contain_exactly("Beta", "Delta")
    end
  end

  describe "#order" do
    it "sorts ascending" do
      results = store.query(QueryTestModels::Item).order(:name).to_a
      expect(results.map(&:name)).to eq(%w[Alpha Beta Delta Epsilon Gamma])
    end

    it "sorts descending" do
      results = store.query(QueryTestModels::Item).order(:name, :desc).to_a
      expect(results.map(&:name)).to eq(%w[Gamma Epsilon Delta Beta Alpha])
    end

    it "sorts by hash syntax" do
      results = store.query(QueryTestModels::Item).order({ year: :desc }).to_a
      expect(results.first.year).to eq(2024)
      expect(results.last.year).to eq(2019)
    end

    it "handles nil values (nulls last)" do
      store.save(QueryTestModels::Item.new(id: "6", name: "Zeta", status: nil, year: 2024))
      results = store.query(QueryTestModels::Item).order(:status).to_a
      expect(results.last.status).to be_nil
    end
  end

  describe "#limit and #offset" do
    it "limits results" do
      results = store.query(QueryTestModels::Item).order(:name).limit(3).to_a
      expect(results.size).to eq(3)
      expect(results.map(&:name)).to eq(%w[Alpha Beta Delta])
    end

    it "offsets results" do
      results = store.query(QueryTestModels::Item).order(:name).offset(2).to_a
      expect(results.size).to eq(3)
      expect(results.map(&:name)).to eq(%w[Delta Epsilon Gamma])
    end

    it "combines limit and offset" do
      results = store.query(QueryTestModels::Item).order(:name).limit(2).offset(1).to_a
      expect(results.size).to eq(2)
      expect(results.map(&:name)).to eq(%w[Beta Delta])
    end
  end

  describe "#reverse_order" do
    it "reverses existing order" do
      results = store.query(QueryTestModels::Item).order(:name).reverse_order.to_a
      expect(results.first.name).to eq("Gamma")
    end
  end

  describe "immutable chains" do
    it "does not mutate original query" do
      base = store.query(QueryTestModels::Item)
      filtered = base.where(status: "published")
      limited = filtered.limit(1)

      expect(base.to_a.size).to eq(5)
      expect(filtered.to_a.size).to eq(3)
      expect(limited.to_a.size).to eq(1)
    end
  end

  describe "terminal methods" do
    describe "#first" do
      it "returns first result" do
        result = store.query(QueryTestModels::Item).order(:name).first
        expect(result.name).to eq("Alpha")
      end

      it "returns nil for empty result" do
        result = store.query(QueryTestModels::Item).where(status: "nonexistent").first
        expect(result).to be_nil
      end
    end

    describe "#last" do
      it "returns last result" do
        result = store.query(QueryTestModels::Item).order(:name).last
        expect(result.name).to eq("Gamma")
      end
    end

    describe "#count" do
      it "counts all records" do
        expect(store.query(QueryTestModels::Item).count).to eq(5)
      end

      it "counts filtered records" do
        expect(store.query(QueryTestModels::Item).where(status: "published").count).to eq(3)
      end

      it "returns size/length aliases" do
        expect(store.query(QueryTestModels::Item).size).to eq(5)
        expect(store.query(QueryTestModels::Item).length).to eq(5)
      end

      it "respects limit" do
        expect(store.query(QueryTestModels::Item).limit(2).count).to eq(2)
      end
    end

    describe "#exists? / #empty?" do
      it "returns true when records exist" do
        expect(store.query(QueryTestModels::Item).where(status: "published").exists?).to be true
      end

      it "returns false when no records" do
        expect(store.query(QueryTestModels::Item).where(status: "nonexistent").exists?).to be false
      end

      it "empty? is inverse of exists?" do
        expect(store.query(QueryTestModels::Item).where(status: "published").empty?).to be false
        expect(store.query(QueryTestModels::Item).where(status: "nonexistent").empty?).to be true
      end
    end

    describe "#one? / #many?" do
      it "one? is true with exactly one match" do
        expect(store.query(QueryTestModels::Item).where(status: "draft").one?).to be true
      end

      it "one? is false with multiple matches" do
        expect(store.query(QueryTestModels::Item).where(status: "published").one?).to be false
      end

      it "many? is true with multiple matches" do
        expect(store.query(QueryTestModels::Item).where(status: "published").many?).to be true
      end
    end

    describe "#find_by" do
      it "finds by conditions" do
        result = store.query(QueryTestModels::Item).find_by(name: "Beta")
        expect(result).not_to be_nil
        expect(result.name).to eq("Beta")
      end

      it "returns nil when not found" do
        result = store.query(QueryTestModels::Item).find_by(name: "NonExistent")
        expect(result).to be_nil
      end
    end

    describe "#find_by!" do
      it "raises when not found" do
        expect do
          store.query(QueryTestModels::Item).find_by!(name: "NonExistent")
        end.to raise_error(Lutaml::Store::ModelNotRegisteredError)
      end
    end
  end

  describe "calculation methods" do
    describe "#pluck" do
      it "plucks single field" do
        names = store.query(QueryTestModels::Item).order(:name).pluck(:name)
        expect(names).to eq(%w[Alpha Beta Delta Epsilon Gamma])
      end

      it "plucks multiple fields" do
        pairs = store.query(QueryTestModels::Item).where(status: "published")
                     .order(:name).pluck(:name, :year)
        expect(pairs).to eq([["Alpha", 2020], ["Epsilon", 2024], ["Gamma", 2023]])
      end
    end

    describe "#distinct" do
      it "returns unique values for a field" do
        statuses = store.query(QueryTestModels::Item).distinct(:status)
        expect(statuses).to contain_exactly("published", "draft", "archived")
      end
    end

    describe "#sum" do
      it "sums a numeric field" do
        total = store.query(QueryTestModels::Item).sum(:year)
        expect(total).to eq(2020 + 2021 + 2023 + 2019 + 2024)
      end
    end

    describe "#average" do
      it "averages a numeric field" do
        avg = store.query(QueryTestModels::Item).average(:score)
        expected = (85.0 + 92.5 + 78.0 + 95.0 + 88.0) / 5
        expect(avg).to be_within(0.01).of(expected)
      end
    end

    describe "#minimum / #maximum" do
      it "returns model with minimum value" do
        result = store.query(QueryTestModels::Item).minimum(:year)
        expect(result.year).to eq(2019)
      end

      it "returns model with maximum value" do
        result = store.query(QueryTestModels::Item).maximum(:year)
        expect(result.year).to eq(2024)
      end
    end
  end

  describe "Enumerable support" do
    it "supports map" do
      names = store.query(QueryTestModels::Item).map(&:name)
      expect(names.size).to eq(5)
    end

    it "supports select" do
      published = store.query(QueryTestModels::Item).select { |m| m.status == "published" }
      expect(published.size).to eq(3)
    end
  end

  describe "DatabaseStore convenience methods" do
    describe "#where" do
      it "delegates to query" do
        results = store.where(model: QueryTestModels::Item, status: "draft")
        expect(results.to_a.size).to eq(1)
        expect(results.first.name).to eq("Beta")
      end
    end

    describe "#all" do
      it "returns Query" do
        results = store.all(model: QueryTestModels::Item)
        expect(results).to be_an_instance_of(Lutaml::Store::Query)
        expect(results.to_a.size).to eq(5)
      end
    end

    describe "#find_by" do
      it "finds by conditions" do
        result = store.find_by(model: QueryTestModels::Item, name: "Delta")
        expect(result.name).to eq("Delta")
      end
    end
  end

  describe "scopes" do
    before do
      store.scope(:published, -> { where(status: "published") })
      store.scope(:recent, -> { where(year: 2023..2024) })
      store.scope(:by_name, ->(name) { where(name: name) })
    end

    it "applies named scope" do
      results = store.query(QueryTestModels::Item).apply(:published).to_a
      expect(results.size).to eq(3)
    end

    it "chains scopes" do
      results = store.query(QueryTestModels::Item).apply(:published).apply(:recent).to_a
      expect(results.size).to eq(2)
      expect(results.map(&:name)).to contain_exactly("Gamma", "Epsilon")
    end

    it "applies scope with arguments" do
      results = store.query(QueryTestModels::Item).apply(:by_name, "Alpha").to_a
      expect(results.size).to eq(1)
      expect(results.first.name).to eq("Alpha")
    end

    it "raises for unknown scope" do
      expect do
        store.query(QueryTestModels::Item).apply(:nonexistent)
      end.to raise_error(ArgumentError, /Unknown scope/)
    end
  end

  describe "batch processing" do
    describe "#find_each" do
      it "yields each record" do
        names = []
        store.query(QueryTestModels::Item).find_each(batch_size: 2) do |item|
          names << item.name
        end
        expect(names.size).to eq(5)
      end

      it "raises with limit set" do
        expect do
          store.query(QueryTestModels::Item).limit(3).find_each { |_i| }
        end.to raise_error(ArgumentError)
      end
    end

    describe "#in_batches" do
      it "yields arrays of records" do
        batch_sizes = []
        store.query(QueryTestModels::Item).in_batches(of: 2) do |batch|
          batch_sizes << batch.size
        end
        expect(batch_sizes).to eq([2, 2, 1])
      end
    end
  end

  describe "transactions" do
    it "executes block atomically" do
      store.transaction do
        store.save(QueryTestModels::Item.new(id: "tx1", name: "TxItem"))
      end

      result = store.fetch(model: QueryTestModels::Item, id: "tx1")
      expect(result.name).to eq("TxItem")
    end
  end
end
