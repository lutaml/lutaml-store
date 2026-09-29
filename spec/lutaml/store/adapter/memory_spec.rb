# frozen_string_literal: true

require_relative "../../../spec_helper"

RSpec.describe Lutaml::Store::Adapter::Memory do
  describe "max_entries capacity bound" do
    it "evicts the oldest inserted entry once the bound is reached" do
      store = described_class.new(max_entries: 3)
      %w[a b c d].each { |k| store.set(k, k) }

      expect(store.keys).to contain_exactly("b", "c", "d")
    end

    it "does not evict when updating an existing key" do
      store = described_class.new(max_entries: 3)
      %w[a b c].each { |k| store.set(k, k) }

      store.set("a", "a2")

      expect(store.keys).to contain_exactly("a", "b", "c")
      expect(store.get("a")).to eq("a2")
    end

    it "grows without bound when max_entries is not configured" do
      store = described_class.new
      50.times { |i| store.set("k#{i}", i) }

      expect(store.size).to eq(50)
    end

    it "bounds bulk_set as well" do
      store = described_class.new(max_entries: 2)
      store.bulk_set([["a", 1], ["b", 2], ["c", 3]])

      expect(store.keys).to contain_exactly("b", "c")
    end

    it "reports the cap through stats" do
      expect(described_class.new(max_entries: 7).stats[:max_entries]).to eq(7)
    end
  end

  describe "BasicStore wiring" do
    it "carries max_entries through BasicStore's adapter options" do
      store = Lutaml::Store::BasicStore.new(
        adapter: { type: :memory, max_entries: 2 },
      )

      store.set("a", 1)
      store.set("b", 2)
      store.set("c", 3)

      expect(store.size).to eq(2)
      expect(store.keys).to contain_exactly("b", "c")
    end

    it "carries max_entries through the inline adapter_type hash" do
      store = Lutaml::Store::BasicStore.new(
        adapter_type: { type: :memory, max_entries: 2 },
      )

      store.set("a", 1)
      store.set("b", 2)
      store.set("c", 3)

      expect(store.size).to eq(2)
    end
  end
end
