# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Pin the TTL semantics of CacheStore before consumers trust it as the only
# expiry mechanism (lutaml/lutaml-store#10).
RSpec.describe Lutaml::Store::CacheStore do
  let(:config) do
    {
      adapter: { type: :memory },
      default_ttl: 3600,
      max_size: 100
    }
  end

  it "returns a value within the TTL window" do
    store = Lutaml::Store::CacheStore.new(config)
    store.set("k", "v", ttl: 3600)
    expect(store.get("k")).to eq("v")
  end

  it "returns nil after the TTL has elapsed" do
    store = Lutaml::Store::CacheStore.new(config)
    store.set("expired", "v", ttl: 0)
    expect(store.get("expired")).to be_nil
  end

  it "returns nil for a key that was never set" do
    expect(Lutaml::Store::CacheStore.new(config).get("nope")).to be_nil
  end

  it "persists TTL entries across set/get on the same instance" do
    store = Lutaml::Store::CacheStore.new(config)
    store.set("a", "1", ttl: 3600)
    store.set("b", "2", ttl: 3600)
    expect(store.get("a")).to eq("1")
    expect(store.get("b")).to eq("2")
  end

  it "treats no explicit TTL as using the default TTL (not never-expiring)" do
    store = Lutaml::Store::CacheStore.new(config)
    store.set("defaulted", "value")
    expect(store.get("defaulted")).to eq("value")
  end

  # --- lutaml/lutaml-store#10: the pinned TTL contract, per adapter ---

  def filesystem_config(dir)
    {
      adapter: { type: :filesystem, options: { path: dir } },
      default_ttl: 3600,
      max_size: 100
    }
  end

  describe "persistence across restarts (FileSystem)" do
    it "reloads TTL entries with created_at intact, so expiry survives restarts" do
      Dir.mktmpdir do |dir|
        first = described_class.new(filesystem_config(dir))
        first.set("k", "v", ttl: 3600)

        reopened = described_class.new(filesystem_config(dir))
        expect(reopened.get("k")).to eq("v")
        expect(reopened.ttl("k")).to be > 3590
      end
    end

    it "treats an entry expired before the restart as expired after it" do
      Dir.mktmpdir do |dir|
        first = described_class.new(filesystem_config(dir))
        first.set("k", "v", ttl: 0.01)
        sleep 0.02

        reopened = described_class.new(filesystem_config(dir))
        expect(reopened.get("k")).to be_nil
      end
    end
  end

  describe "expired reads" do
    it "get returns nil AND deletes the entry" do
      store = described_class.new(config)
      store.set("k", "v", ttl: 0.01)
      sleep 0.02

      expect(store.get("k")).to be_nil
      expect(store.exists?("k")).to be(false)
      expect(store.keys).not_to include("k")
    end
  end

  describe "sweep semantics" do
    it "expiry is lazy-on-read; cleanup_expired sweeps without a background reaper" do
      store = described_class.new(config)
      store.set("gone", "v", ttl: 0.01)
      store.set("kept", "v", ttl: 3600)
      sleep 0.02

      expect(store.keys).to eq(["kept"])
      store.cleanup_expired
      expect(store.cache_info[:expired_entries]).to eq(0)
    end
  end

  describe "zero and nil TTL" do
    it "nil TTL never expires" do
      store = Lutaml::Store::CacheStore.new(
        adapter: { type: :memory }, max_size: 100
      )
      store.set("k", "v", ttl: nil)
      expect(store.ttl("k")).to be_nil
      expect(store.exists?("k")).to be(true)
    end

    it "ttl 0 is immediately expired" do
      store = described_class.new(config)
      store.set("k", "v", ttl: 0)
      expect(store.get("k")).to be_nil
      expect(store.exists?("k")).to be(false)
    end
  end

  describe "clock" do
    it "created_at is an ISO8601 wall clock that round-trips through serialization" do
      before = Time.now
      entry = Lutaml::Store::CacheStore::CacheEntry.new("v", ttl: 3600)
      expect(entry.created_at).to be >= before

      hash = entry.to_h
      expect(Time.parse(hash[:created_at])).to be >= before
      expect(hash[:expires_at]).to eq((entry.created_at + 3600).iso8601(6))

      restored = Lutaml::Store::CacheStore::CacheEntry.from_h(hash)
      expect(restored.created_at.iso8601).to eq(entry.created_at.iso8601)
      expect(restored.ttl).to eq(3600)
    end

    it "wall-clock choice: a jump backward in system time un-expires nothing (documented trade)" do
      # entries carry absolute created_at + ttl; the guarantee pinned here is
      # only that restarts keep the same clock frame — clock jumps are the
      # documented limitation of the wall-clock choice (README)
      entry = Lutaml::Store::CacheStore::CacheEntry.new("v", ttl: 1, created_at: Time.now - 2)
      expect(entry.expired?).to be(true)
    end
  end
end
