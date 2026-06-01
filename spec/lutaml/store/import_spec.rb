# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

class ImportTestItem < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :category, :string

  key_value do
    map :name, to: :name
    map :category, to: :category
  end
end

RSpec.describe "Lutaml::Store import workflow" do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.rm_rf(tmpdir) }

  let(:store) do
    Lutaml::Store.new(
      adapter: :memory,
      models: [{ model: ImportTestItem, key: :name, dir: "items" }]
    )
  end

  let(:items) do
    [
      ImportTestItem.new(name: "alpha", category: "primary"),
      ImportTestItem.new(name: "beta", category: "secondary"),
      ImportTestItem.new(name: "gamma", category: "primary")
    ]
  end

  describe "#import_all" do
    before do
      store.save_all(items, path: tmpdir, format: :yaml, layout: :separate)
    end

    it "loads from directory and stores into key-value backend" do
      fresh_store = Lutaml::Store.new(
        adapter: :memory,
        models: [{ model: ImportTestItem, key: :name, dir: "items" }]
      )

      loaded = fresh_store.import_all(ImportTestItem, path: tmpdir, format: :yaml, layout: :separate)
      expect(loaded.size).to eq(3)

      # Now queryable via fetch
      fetched = fresh_store.fetch(model: ImportTestItem, name: "alpha")
      expect(fetched).not_to be_nil
      expect(fetched.name).to eq("alpha")
      expect(fetched.category).to eq("primary")
    end

    it "supports where queries after import" do
      fresh_store = Lutaml::Store.new(
        adapter: :memory,
        models: [{ model: ImportTestItem, key: :name, dir: "items" }]
      )

      fresh_store.import_all(ImportTestItem, path: tmpdir, format: :yaml, layout: :separate)

      primary = fresh_store.where(model: ImportTestItem, category: "primary")
      expect(primary.size).to eq(2)
      expect(primary.map(&:name).sort).to eq(%w[alpha gamma])
    end

    it "supports count after import" do
      fresh_store = Lutaml::Store.new(
        adapter: :memory,
        models: [{ model: ImportTestItem, key: :name, dir: "items" }]
      )

      fresh_store.import_all(ImportTestItem, path: tmpdir, format: :yaml, layout: :separate)
      expect(fresh_store.count(model: ImportTestItem)).to eq(3)
    end

    it "supports exists? after import" do
      fresh_store = Lutaml::Store.new(
        adapter: :memory,
        models: [{ model: ImportTestItem, key: :name, dir: "items" }]
      )

      fresh_store.import_all(ImportTestItem, path: tmpdir, format: :yaml, layout: :separate)
      expect(fresh_store.exists?(model: ImportTestItem, name: "beta")).to be true
      expect(fresh_store.exists?(model: ImportTestItem, name: "missing")).to be false
    end
  end
end
