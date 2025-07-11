# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::Store do
  let(:store) { described_class.new }

  describe "initialization" do
    it "creates a store with default memory adapter" do
      expect(store.adapter).to be_a(Lutaml::Store::Adapter::Memory)
    end

    it "creates a store with configuration hash" do
      config = {
        "adapter" => { "type" => "memory" },
        "cache" => { "enabled" => false }
      }
      store = described_class.new(config)
      expect(store.cache).to be_nil
    end

    it "creates a store with direct adapter instance" do
      adapter = Lutaml::Store::Adapter::Memory.new
      store = described_class.new(adapter)
      expect(store.adapter).to eq(adapter)
    end
  end

  describe "basic operations" do
    it "stores and retrieves values" do
      store.set("key1", "value1")
      expect(store.get("key1")).to eq("value1")
    end

    it "returns nil for non-existent keys" do
      expect(store.get("nonexistent")).to be_nil
    end

    it "deletes values" do
      store.set("key1", "value1")
      expect(store.delete("key1")).to be true
      expect(store.get("key1")).to be_nil
    end

    it "checks key existence" do
      store.set("key1", "value1")
      expect(store.exists?("key1")).to be true
      expect(store.exists?("nonexistent")).to be false
    end

    it "returns all data" do
      store.set("key1", "value1")
      store.set("key2", "value2")
      expect(store.all).to eq("key1" => "value1", "key2" => "value2")
    end

    it "clears all data" do
      store.set("key1", "value1")
      store.clear
      expect(store.size).to eq(0)
    end

    it "returns correct size" do
      expect(store.size).to eq(0)
      store.set("key1", "value1")
      expect(store.size).to eq(1)
    end
  end

  describe "caching" do
    let(:config) do
      {
        "adapter" => { "type" => "memory" },
        "cache" => { "enabled" => true, "max_size" => 10 }
      }
    end
    let(:store) { described_class.new(config) }

    it "caches retrieved values" do
      store.set("key1", "value1")

      # First get should hit backend
      value1 = store.get("key1")
      expect(value1).to eq("value1")

      # Second get should hit cache
      value2 = store.get("key1")
      expect(value2).to eq("value1")

      # Cache should contain the value
      expect(store.cache_stats[:size]).to eq(1)
    end

    it "invalidates cache on delete" do
      store.set("key1", "value1")
      store.get("key1") # Cache the value

      store.delete("key1")
      expect(store.cache_stats[:size]).to eq(0)
    end
  end

  describe "events" do
    let(:events) { [] }

    before do
      store.on(:set) { |data| events << data }
      store.on(:get) { |data| events << data }
      store.on(:delete) { |data| events << data }
    end

    it "emits events for operations" do
      store.set("key1", "value1")
      store.get("key1")
      store.delete("key1")

      expect(events.size).to eq(3)
      expect(events[0][:event]).to eq(:set)
      expect(events[1][:event]).to eq(:get)
      expect(events[2][:event]).to eq(:delete)
    end
  end

  describe "monitoring" do
    let(:config) do
      {
        "adapter" => { "type" => "memory" },
        "monitoring" => { "enabled" => true }
      }
    end
    let(:store) { described_class.new(config) }

    it "tracks operation statistics" do
      store.set("key1", "value1")
      store.get("key1")

      stats = store.stats
      monitor_stats = stats[:monitor_stats]
      expect(monitor_stats[:operations][:set]).to eq(1)
      expect(monitor_stats[:operations][:get]).to eq(1)
      # Note: total_operations includes the size call from stats method
      expect(monitor_stats[:total_operations]).to be >= 2
    end
  end

  describe "configuration from file" do
    let(:config_file) { "test_config.yml" }
    let(:config_content) do
      <<~YAML
        lutaml_store:
          adapter:
            type: memory
          cache:
            enabled: true
            max_size: 500
          monitoring:
            enabled: true
      YAML
    end

    before do
      File.write(config_file, config_content)
    end

    after do
      File.delete(config_file) if File.exist?(config_file)
    end

    it "loads configuration from YAML file" do
      store = described_class.from_file(config_file)
      expect(store.adapter).to be_a(Lutaml::Store::Adapter::Memory)
      expect(store.cache).not_to be_nil
      expect(store.monitor).not_to be_nil
    end
  end

  describe "#close" do
    it "closes resources properly" do
      expect { store.close }.not_to raise_error
    end
  end
end
