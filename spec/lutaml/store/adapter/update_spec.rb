# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Adapter#update and #each_key" do
  describe Lutaml::Store::Adapter::Base do
    let(:adapter_class) do
      Class.new(described_class) do
        def initialize(config = {})
          super
          @data = {}
        end

        def get(key) = @data[key]
        def set(key, value) = (@data[key] = value)
        def keys = @data.keys
      end
    end

    it "derives each_key from keys" do
      adapter = adapter_class.new
      adapter.set("a", 1)
      adapter.set("b", 2)

      expect(adapter.each_key.to_a).to eq(%w[a b])
      yielded = []
      adapter.each_key { |k| yielded << k }
      expect(yielded).to eq(%w[a b])
    end

    it "provides a default update from get and set" do
      adapter = adapter_class.new
      adapter.set("n", 1)

      expect(adapter.update("n") { |v| v + 1 }).to eq(2)
      expect(adapter.get("n")).to eq(2)
    end
  end

  describe Lutaml::Store::Adapter::Memory do
    it "makes update atomic across threads" do
      adapter = described_class.new
      adapter.set("n", 0)
      Array.new(8) { Thread.new { 200.times { adapter.update("n") { |v| v + 1 } } } }.each(&:join)

      expect(adapter.get("n")).to eq(1600)
    end

    it "keeps the expiry of an updated key" do
      adapter = described_class.new(ttl_enabled: true, default_ttl: 3600)
      adapter.set("n", 1, ttl: 60)
      adapter.update("n") { |v| v + 1 }

      expect(adapter.get_ttl("n")).to be <= 60
    end
  end

  describe Lutaml::Store::BasicStore do
    it "updates the adapter and the read cache" do
      store = described_class.new(adapter_type: :memory)
      store.set("n", 1)
      store.get("n")

      expect(store.update("n") { |v| v + 1 }).to eq(2)
      expect(store.get("n")).to eq(2)
      expect(store.adapter.get("n")).to eq(2)
    end
  end
end
