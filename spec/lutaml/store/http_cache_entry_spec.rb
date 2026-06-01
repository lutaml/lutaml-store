# frozen_string_literal: true

require "spec_helper"
require "lutaml/store/http_cache_entry"

RSpec.describe Lutaml::Store::HttpCacheEntry do
  let(:cache_entry) do
    described_class.new(
      cache_key: "GET:http://example.com/api",
      url: "http://example.com/api",
      method: "GET",
      request_headers: { "accept" => "application/json" },
      response_body: '{"test": "data"}',
      response_headers: { "content-type" => "application/json" },
      status_code: 200,
      cached_at: Time.now - 1800, # 30 minutes ago
      etag: '"abc123"',
      last_modified: Time.now - 3600, # 1 hour ago
      expires_at: Time.now + 1800, # 30 minutes from now
      max_age: 3600,
      cache_control: { "max-age" => 3600 },
      vary_headers: ["accept-encoding"]
    )
  end

  describe "#fresh?" do
    context "when entry is not expired and doesn't require revalidation" do
      it "returns true" do
        expect(cache_entry.fresh?).to be true
      end
    end

    context "when entry is expired" do
      before do
        cache_entry.expires_at = Time.now - 100
      end

      it "returns false" do
        expect(cache_entry.fresh?).to be false
      end
    end

    context "when entry must revalidate" do
      before do
        cache_entry.cache_control = { "must-revalidate" => true }
      end

      it "returns false" do
        expect(cache_entry.fresh?).to be false
      end
    end
  end

  describe "#expired?" do
    context "when expires_at is in the past" do
      before do
        cache_entry.expires_at = Time.now - 100
      end

      it "returns true" do
        expect(cache_entry.expired?).to be true
      end
    end

    context "when max_age is exceeded" do
      before do
        cache_entry.cached_at = Time.now - 7200 # 2 hours ago
        cache_entry.max_age = 3600 # 1 hour
      end

      it "returns true" do
        expect(cache_entry.expired?).to be true
      end
    end

    context "when entry is still valid" do
      it "returns false" do
        expect(cache_entry.expired?).to be false
      end
    end
  end

  describe "#must_revalidate?" do
    context "with must-revalidate directive" do
      before do
        cache_entry.cache_control = { "must-revalidate" => true }
      end

      it "returns true" do
        expect(cache_entry.must_revalidate?).to be true
      end
    end

    context "with no-cache directive" do
      before do
        cache_entry.cache_control = { "no-cache" => true }
      end

      it "returns true" do
        expect(cache_entry.must_revalidate?).to be true
      end
    end

    context "without revalidation directives" do
      it "returns false" do
        expect(cache_entry.must_revalidate?).to be false
      end
    end
  end

  describe "#stale?" do
    it "returns opposite of fresh?" do
      expect(cache_entry.stale?).to eq(!cache_entry.fresh?)
    end
  end

  describe "#cacheable?" do
    context "with successful status code" do
      it "returns true" do
        expect(cache_entry.cacheable?).to be true
      end
    end

    context "with error status code" do
      before do
        cache_entry.status_code = 404
      end

      it "returns false" do
        expect(cache_entry.cacheable?).to be false
      end
    end

    context "with no-store directive" do
      before do
        cache_entry.cache_control = { "no-store" => true }
      end

      it "returns false" do
        expect(cache_entry.cacheable?).to be false
      end
    end

    context "with private directive" do
      before do
        cache_entry.cache_control = { "private" => true }
      end

      it "returns false" do
        expect(cache_entry.cacheable?).to be false
      end
    end
  end

  describe "#age" do
    it "returns time since cached" do
      age = cache_entry.age
      expect(age).to be_within(1).of(1800) # approximately 30 minutes
    end
  end

  describe "#remaining_ttl" do
    context "when not expired" do
      it "returns remaining time to live" do
        ttl = cache_entry.remaining_ttl
        expect(ttl).to be_within(1).of(1800) # approximately 30 minutes
      end
    end

    context "when expired" do
      before do
        cache_entry.expires_at = Time.now - 100
      end

      it "returns 0" do
        expect(cache_entry.remaining_ttl).to eq(0)
      end
    end

    context "when no expiry set" do
      before do
        cache_entry.expires_at = nil
      end

      it "returns infinity" do
        expect(cache_entry.remaining_ttl).to eq(Float::INFINITY)
      end
    end
  end

  describe "serialization" do
    it "can be serialized and deserialized" do
      hash = cache_entry.to_hash
      restored = described_class.from_hash(hash)

      expect(restored.cache_key).to eq(cache_entry.cache_key)
      expect(restored.url).to eq(cache_entry.url)
      expect(restored.method).to eq(cache_entry.method)
      expect(restored.status_code).to eq(cache_entry.status_code)
      expect(restored.response_body).to eq(cache_entry.response_body)
    end
  end
end
