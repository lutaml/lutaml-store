# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

module FileSystemIntegrationModels
  class Row < Lutaml::Model::Serializable
    attribute :key, :string
    attribute :status, :string
  end
end

RSpec.describe "FileSystem adapter integration" do
  around do |example|
    Dir.mktmpdir("lutaml-store-fs-int") do |dir|
      @dir = dir
      example.run
    end
  end

  let(:row_class) { FileSystemIntegrationModels::Row }

  describe Lutaml::Store::DatabaseStore do
    def new_store
      described_class.new(adapter: :filesystem,
                          adapter_options: { path: File.join(@dir, "db") },
                          models: [{ model: FileSystemIntegrationModels::Row, key: :key }])
    end

    it "reads a saved record back in a new store" do
      new_store.save(row_class.new(key: "a", status: "doc"))

      fetched = new_store.fetch(model: row_class, key: "a")
      expect(fetched.status).to eq("doc")
    end

    it "lists saved records with all(model:) in a new store" do
      new_store.save([row_class.new(key: "a", status: "x"), row_class.new(key: "ISO/19115", status: "y")])

      expect(new_store.all(model: row_class).map(&:key)).to contain_exactly("a", "ISO/19115")
    end

    it "accepts the README adapter hash form" do
      store = described_class.new(adapter: { type: :filesystem, path: File.join(@dir, "readme") },
                                  models: [{ model: FileSystemIntegrationModels::Row, key: :key }])
      store.save(row_class.new(key: "a", status: "doc"))

      expect(store.store.adapter).to be_a(Lutaml::Store::Adapter::FileSystem)
      expect(Dir.exist?(File.join(@dir, "readme"))).to be(true)
    end
  end

  describe Lutaml::Store::CacheStore do
    let(:cache) do
      described_class.new(adapter: { type: :filesystem, options: { path: File.join(@dir, "ttl") } },
                          default_ttl: 60, cleanup_interval: 0)
    end

    it "works after cleanup_interval has passed" do
      cache.set("x", { "status" => "not_found" })

      expect(cache.get("x")).to eq({ status: "not_found" })
      expect(cache.cleanup_expired).to eq(0)
    end

    it "removes expired entries on cleanup" do
      manual = described_class.new(adapter: { type: :filesystem, options: { path: File.join(@dir, "manual") } },
                                   cleanup_interval: 3600)
      manual.set("old", "v", ttl: -1)
      manual.set("new", "v")

      expect(manual.cleanup_expired).to eq(1)
      expect(manual.adapter.keys).to eq(["new"])
    end

    it "runs the periodic cleanup from set" do
      cache.set("old", "v", ttl: -1)
      cache.set("new", "v")

      expect(cache.adapter.keys).to eq(["new"])
    end
  end

  describe Lutaml::Store::Config do
    it "moves options from an adapter hash into adapter_options" do
      config = described_class.new(adapter_type: { type: :filesystem, path: "./data", extension: ".json" })

      expect(config.adapter_type).to eq(:filesystem)
      expect(config.adapter_options).to eq(path: "./data", extension: ".json")
    end

    it "reads a nested options hash and lets explicit adapter_options win" do
      config = described_class.new(adapter_type: { type: :sqlite, options: { path: "a.db", timeout: 5 } },
                                   adapter_options: { path: "b.db" })

      expect(config.adapter_options).to eq(path: "b.db", timeout: 5)
    end
  end
end

RSpec.describe Lutaml::Store::CacheStore, "thread safety" do
  it "survives LRU eviction under concurrent set and get" do
    cache = described_class.new(max_size: 50, cleanup_interval: 0)
    errors = Queue.new
    threads = Array.new(8) do |t|
      Thread.new do
        300.times do |i|
          key = "t#{t}-#{i % 80}"
          cache.set(key, i)
          cache.get(key)
        rescue StandardError => e
          errors << e
        end
      end
    end
    threads.each(&:join)

    expect(errors.size).to eq(0)
    expect(cache.size).to be <= 50
  end
end
