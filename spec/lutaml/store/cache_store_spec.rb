# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::CacheStore do
  let(:config) do
    {
      adapter: {
        type: :memory
      },
      default_ttl: 60,
      max_size: 100,
      cleanup_interval: 10
    }
  end
  let(:cache) { described_class.new(config) }

  describe "CacheEntry" do
    let(:entry) { described_class::CacheEntry.new("value", ttl: 60, metadata: { source: "test" }) }

    it "tracks creation time" do
      expect(entry.created_at).to be_within(1).of(Time.now)
    end

    it "calculates expiration" do
      expect(entry.expired?).to be false

      # Simulate time passing
      allow(Time).to receive(:now).and_return(entry.created_at + 61)
      expect(entry.expired?).to be true
    end

    it "calculates expires_at" do
      expect(entry.expires_at).to be_within(1).of(entry.created_at + 60)
    end

    it "serializes to hash" do
      hash = entry.to_h
      expect(hash).to include(:value, :created_at, :ttl, :expires_at, :metadata)
      expect(hash[:value]).to eq("value")
      expect(hash[:ttl]).to eq(60)
      expect(hash[:metadata]).to eq({ source: "test" })
    end

    it "deserializes from hash" do
      hash = entry.to_h
      restored = described_class::CacheEntry.from_h(hash)

      expect(restored.value).to eq(entry.value)
      expect(restored.ttl).to eq(entry.ttl)
      expect(restored.metadata).to eq(entry.metadata)
      expect(restored.created_at).to be_within(1).of(entry.created_at)
    end
  end

  describe "#set and #get" do
    it "stores and retrieves values" do
      cache.set("key1", "value1")
      expect(cache.get("key1")).to eq("value1")
    end

    it "returns nil for non-existent keys" do
      expect(cache.get("nonexistent")).to be_nil
    end

    it "respects TTL" do
      cache.set("key1", "value1", ttl: 1)
      expect(cache.get("key1")).to eq("value1")

      # Simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + 2)
      expect(cache.get("key1")).to be_nil
    end

    it "uses default TTL when not specified" do
      cache.set("key1", "value1")
      expect(cache.ttl("key1")).to be_within(5).of(60)
    end

    it "stores metadata" do
      cache.set("key1", "value1", metadata: { source: "api" })

      entry_data = cache.adapter.get("key1")
      parsed = JSON.parse(entry_data, symbolize_names: true)
      expect(parsed[:metadata]).to eq({ source: "api" })
    end
  end

  describe "#exists?" do
    it "returns true for existing non-expired keys" do
      cache.set("key1", "value1")
      expect(cache.exists?("key1")).to be true
    end

    it "returns false for non-existent keys" do
      expect(cache.exists?("nonexistent")).to be false
    end

    it "returns false for expired keys" do
      cache.set("key1", "value1", ttl: 1)

      # Simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + 2)
      expect(cache.exists?("key1")).to be false
    end
  end

  describe "#ttl" do
    it "returns remaining TTL" do
      cache.set("key1", "value1", ttl: 60)
      expect(cache.ttl("key1")).to be_within(5).of(60)
    end

    it "returns nil for keys without TTL" do
      cache.set("key1", "value1", ttl: nil)
      expect(cache.ttl("key1")).to be_nil
    end

    it "returns nil for expired keys" do
      cache.set("key1", "value1", ttl: 1)

      # Simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + 2)
      expect(cache.ttl("key1")).to be_nil
    end
  end

  describe "#touch" do
    it "updates TTL for existing key" do
      cache.set("key1", "value1", ttl: 60)
      cache.ttl("key1")

      # Simulate some time passing
      allow(Time).to receive(:now).and_return(Time.now + 30)

      expect(cache.touch("key1", ttl: 120)).to be true
      expect(cache.ttl("key1")).to be_within(5).of(120)
    end

    it "returns false for non-existent keys" do
      expect(cache.touch("nonexistent")).to be false
    end

    it "returns false for expired keys" do
      cache.set("key1", "value1", ttl: 1)

      # Simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + 2)
      expect(cache.touch("key1")).to be false
    end
  end

  describe "#fetch" do
    it "returns existing value" do
      cache.set("key1", "value1")

      result = cache.fetch("key1") { "new_value" }
      expect(result).to eq("value1")
    end

    it "executes block for missing key" do
      result = cache.fetch("key1") { "new_value" }
      expect(result).to eq("new_value")
      expect(cache.get("key1")).to eq("new_value")
    end

    it "returns nil for missing key without block" do
      result = cache.fetch("key1")
      expect(result).to be_nil
    end

    it "respects TTL in fetch" do
      result = cache.fetch("key1", ttl: 30) { "new_value" }
      expect(result).to eq("new_value")
      expect(cache.ttl("key1")).to be_within(5).of(30)
    end
  end

  describe "#cleanup_expired" do
    it "removes expired entries" do
      cache.set("key1", "value1", ttl: 1)
      cache.set("key2", "value2", ttl: 60)

      # Simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + 2)

      expired_count = cache.cleanup_expired
      expect(expired_count).to eq(1)
      expect(cache.exists?("key1")).to be false
      expect(cache.exists?("key2")).to be true
    end
  end

  describe "#cache_info" do
    it "provides cache statistics" do
      cache.set("key1", "value1", ttl: 1)
      cache.set("key2", "value2", ttl: 60)

      # Simulate time passing to expire one entry
      allow(Time).to receive(:now).and_return(Time.now + 2)

      info = cache.cache_info
      expect(info).to include(:total_entries, :valid_entries, :expired_entries, :max_size, :default_ttl)
      expect(info[:total_entries]).to eq(2)
      expect(info[:valid_entries]).to eq(1)
      expect(info[:expired_entries]).to eq(1)
    end
  end

  describe "LRU eviction" do
    let(:small_cache) { described_class.new(config.merge(max_size: 2)) }

    it "evicts least recently used entries when max size is reached" do
      small_cache.set("key1", "value1")
      small_cache.set("key2", "value2")

      # Access key1 to make it more recently used
      small_cache.get("key1")

      # Adding key3 should evict key2 (least recently used)
      small_cache.set("key3", "value3")

      expect(small_cache.exists?("key1")).to be true
      expect(small_cache.exists?("key2")).to be false
      expect(small_cache.exists?("key3")).to be true
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")

      cache.clear

      expect(cache.size).to eq(0)
      expect(cache.exists?("key1")).to be false
      expect(cache.exists?("key2")).to be false
    end
  end

  describe "#delete" do
    it "removes specific entry" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")

      deleted_value = cache.delete("key1")

      expect(deleted_value).to eq("value1")
      expect(cache.exists?("key1")).to be false
      expect(cache.exists?("key2")).to be true
    end
  end

  describe "automatic cleanup" do
    let(:auto_cache) { described_class.new(config.merge(cleanup_interval: 1)) }

    it "automatically cleans up expired entries" do
      auto_cache.set("key1", "value1", ttl: 1)

      # Simulate time passing beyond cleanup interval and TTL
      allow(Time).to receive(:now).and_return(Time.now + 2)

      # Next operation should trigger cleanup
      auto_cache.set("key2", "value2")

      expect(auto_cache.exists?("key1")).to be false
      expect(auto_cache.exists?("key2")).to be true
    end
  end
end
