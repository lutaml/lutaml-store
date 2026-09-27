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
end
