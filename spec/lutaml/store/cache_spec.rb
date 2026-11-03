# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::Cache do
  subject(:cache) { described_class.new(max_size: max_size, ttl: ttl) }

  let(:max_size) { 3 }
  let(:ttl) { nil }

  describe "#set and #get" do
    it "round-trips values" do
      cache.set("a", { "x" => 1 })

      expect(cache.get("a")).to eq({ "x" => 1 })
    end

    it "returns nil for missing keys" do
      expect(cache.get("missing")).to be_nil
    end

    it "overwrites existing keys" do
      cache.set("a", 1)
      cache.set("a", 2)

      expect(cache.get("a")).to eq(2)
    end
  end

  describe "LRU eviction" do
    it "evicts the least recently used entry beyond max_size" do
      cache.set("a", 1)
      cache.set("b", 2)
      cache.set("c", 3)
      cache.set("d", 4)

      expect(cache.exists?("a")).to be(false)
      expect(cache.get("b")).to eq(2)
      expect(cache.get("c")).to eq(3)
      expect(cache.get("d")).to eq(4)
    end

    it "refreshes recency on get" do
      cache.set("a", 1)
      cache.set("b", 2)
      cache.set("c", 3)
      cache.get("a")
      cache.set("d", 4)

      expect(cache.exists?("b")).to be(false)
      expect(cache.get("a")).to eq(1)
    end

    it "refreshes recency on set" do
      cache.set("a", 1)
      cache.set("b", 2)
      cache.set("c", 3)
      cache.set("a", 10)
      cache.set("d", 4)

      expect(cache.exists?("b")).to be(false)
      expect(cache.get("a")).to eq(10)
    end

    it "stays bounded at max_size" do
      100.times { |i| cache.set("k#{i}", i) }

      expect(cache.size).to eq(3)
    end
  end

  describe "#delete" do
    it "removes an existing key and reports true" do
      cache.set("a", 1)

      expect(cache.delete("a")).to be(true)
      expect(cache.exists?("a")).to be(false)
    end

    it "reports false for a missing key" do
      expect(cache.delete("missing")).to be(false)
    end
  end

  describe "#clear and #size" do
    it "empties the cache" do
      cache.set("a", 1)
      cache.set("b", 2)
      cache.clear

      expect(cache.size).to eq(0)
      expect(cache.get("a")).to be_nil
    end
  end

  describe "TTL expiry" do
    let(:ttl) { 0.05 }

    it "expires entries past the ttl" do
      cache.set("a", 1)

      expect(cache.get("a")).to eq(1)

      sleep 0.06

      expect(cache.get("a")).to be_nil
      expect(cache.exists?("a")).to be(false)
    end

    it "reports expired entries through cleanup_expired" do
      cache.set("a", 1)
      sleep 0.06

      expect(cache.cleanup_expired).to eq(1)
      expect(cache.size).to eq(0)
    end
  end

  describe "#stats" do
    it "reports size, bounds and keys" do
      cache.set("a", 1)

      expect(cache.stats).to include(size: 1, max_size: 3, ttl: nil)
      expect(cache.stats[:keys]).to eq(["a"])
    end
  end

  describe "O(1) recency maintenance" do
    it "serves hits at constant cost regardless of size" do
      big = described_class.new(max_size: 2000)
      2000.times { |i| big.set("k#{i}", i) }
      small = described_class.new(max_size: 10)
      10.times { |i| small.set("k#{i}", i) }

      def hit_time(cache, keys)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        20_000.times { |i| cache.get(keys[i % keys.size]) }
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      end

      big_keys = (0...2000).map { |i| "k#{i}" }
      small_keys = (0...10).map { |i| "k#{i}" }
      big_us = hit_time(big, big_keys) / 20_000 * 1_000_000
      small_us = hit_time(small, small_keys) / 20_000 * 1_000_000

      expect(big_us).to be < small_us * 10
    end
  end
end
