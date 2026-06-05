# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Lutaml::Store::HttpCache do
  let(:cache_config) do
    {
      adapter_type: "memory",
      default_ttl: 3600,
      respect_http_headers: true,
      enable_conditional_requests: true
    }
  end

  let(:http_cache) { described_class.new(cache_config) }

  describe "#initialize" do
    it "accepts hash configuration" do
      cache = described_class.new(cache_config)
      expect(cache).to be_a(described_class)
    end

    it "accepts HttpCacheConfig object" do
      config = Lutaml::Store::HttpCacheConfig.new(cache_config)
      cache = described_class.new(config)
      expect(cache).to be_a(described_class)
    end

    it "validates configuration" do
      invalid_config = { adapter_type: "memory", default_ttl: -1 }
      expect { described_class.new(invalid_config) }.to raise_error(ArgumentError)
    end
  end

  describe "#fetch" do
    let(:url) { "http://example.com/api" }
    let(:method) { "GET" }
    let(:headers) { { "accept" => "application/json" } }
    let(:response_data) do
      {
        status_code: 200,
        headers: { "content-type" => "application/json", "cache-control" => "max-age=3600" },
        body: '{"test": "data"}'
      }
    end

    it "requires a block" do
      expect { http_cache.fetch(method, url, headers) }.to raise_error(ArgumentError)
    end

    context "cache miss" do
      it "calls block and caches response" do
        block_called = false
        result = http_cache.fetch(method, url, headers) do |request_headers|
          block_called = true
          expect(request_headers).to eq(headers)
          response_data
        end

        expect(block_called).to be true
        expect(result).to eq(response_data)
      end

      it "stores cacheable responses" do
        http_cache.fetch(method, url, headers) { response_data }

        # Second request should use cache
        block_called = false
        result = http_cache.fetch(method, url, headers) do
          block_called = true
          raise "Should not be called"
        end

        expect(block_called).to be false
        expect(result).to eq(response_data)
      end
    end

    context "cache hit" do
      before do
        http_cache.fetch(method, url, headers) { response_data }
      end

      it "returns cached response without calling block" do
        block_called = false
        result = http_cache.fetch(method, url, headers) do
          block_called = true
          raise "Should not be called"
        end

        expect(block_called).to be false
        expect(result).to eq(response_data)
      end
    end

    context "conditional requests" do
      let(:etag_response) do
        {
          status_code: 200,
          headers: { "etag" => '"abc123"', "cache-control" => "max-age=1" },
          body: "original data"
        }
      end

      it "makes conditional request for stale entries" do
        # Cache initial response
        http_cache.fetch(method, url, headers) { etag_response }

        # Wait for entry to become stale
        sleep(1.1)

        # Should make conditional request
        conditional_request_made = false
        result = http_cache.fetch(method, url, headers) do |request_headers|
          conditional_request_made = true
          expect(request_headers["If-None-Match"]).to eq('"abc123"')
          { status_code: 304, headers: {}, body: "" }
        end

        expect(conditional_request_made).to be true
        expect(result[:body]).to eq("original data") # Returns cached body
        expect(result[:status_code]).to eq(200) # Returns cached status
      end

      it "caches new response when content is modified" do
        # Cache initial response
        http_cache.fetch(method, url, headers) { etag_response }

        # Wait for entry to become stale
        sleep(1.1)

        new_response = {
          status_code: 200,
          headers: { "etag" => '"def456"' },
          body: "new data"
        }

        result = http_cache.fetch(method, url, headers) do |request_headers|
          expect(request_headers["If-None-Match"]).to eq('"abc123"')
          new_response
        end

        expect(result).to eq(new_response)
      end
    end

    context "uncacheable responses" do
      let(:error_response) do
        {
          status_code: 404,
          headers: {},
          body: "Not Found"
        }
      end

      it "does not cache error responses" do
        result1 = http_cache.fetch(method, url, headers) { error_response }
        expect(result1).to eq(error_response)

        # Second request should call block again
        block_called = false
        result2 = http_cache.fetch(method, url, headers) do
          block_called = true
          error_response
        end

        expect(block_called).to be true
        expect(result2).to eq(error_response)
      end

      it "does not cache no-store responses" do
        no_store_response = {
          status_code: 200,
          headers: { "cache-control" => "no-store" },
          body: "sensitive data"
        }

        result1 = http_cache.fetch(method, url, headers) { no_store_response }
        expect(result1).to eq(no_store_response)

        # Second request should call block again
        block_called = false
        http_cache.fetch(method, url, headers) do
          block_called = true
          no_store_response
        end

        expect(block_called).to be true
      end
    end
  end

  describe "#get" do
    let(:url) { "http://example.com/api" }
    let(:method) { "GET" }
    let(:headers) { { "accept" => "application/json" } }
    let(:response_data) do
      {
        status_code: 200,
        headers: { "content-type" => "application/json" },
        body: '{"test": "data"}'
      }
    end

    it "returns nil for cache miss" do
      result = http_cache.get(method, url, headers)
      expect(result).to be_nil
    end

    it "returns cached response for cache hit" do
      # Cache a response first
      http_cache.fetch(method, url, headers) { response_data }

      # Get should return cached response
      result = http_cache.get(method, url, headers)
      expect(result).to eq(response_data)
    end

    it "returns nil for stale entries" do
      stale_response = {
        status_code: 200,
        headers: { "cache-control" => "max-age=1" },
        body: "data"
      }

      # Cache a response
      http_cache.fetch(method, url, headers) { stale_response }

      # Wait for it to become stale
      sleep(1.1)

      # Get should return nil for stale entry
      result = http_cache.get(method, url, headers)
      expect(result).to be_nil
    end
  end

  describe "#set" do
    let(:url) { "http://example.com/api" }
    let(:method) { "GET" }
    let(:headers) { { "accept" => "application/json" } }
    let(:response_data) do
      {
        status_code: 200,
        headers: { "content-type" => "application/json" },
        body: '{"test": "data"}'
      }
    end

    it "stores cacheable response" do
      result = http_cache.set(method, url, headers, response_data)
      expect(result).to eq(response_data)

      # Verify it was cached
      cached = http_cache.get(method, url, headers)
      expect(cached).to eq(response_data)
    end

    it "does not store uncacheable response" do
      error_response = {
        status_code: 404,
        headers: {},
        body: "Not Found"
      }

      result = http_cache.set(method, url, headers, error_response)
      expect(result).to eq(error_response)

      # Verify it was not cached
      cached = http_cache.get(method, url, headers)
      expect(cached).to be_nil
    end
  end

  describe "#delete" do
    let(:url) { "http://example.com/api" }
    let(:method) { "GET" }
    let(:headers) { { "accept" => "application/json" } }
    let(:response_data) do
      {
        status_code: 200,
        headers: { "content-type" => "application/json" },
        body: '{"test": "data"}'
      }
    end

    it "removes cached entry" do
      # Cache a response
      http_cache.set(method, url, headers, response_data)
      expect(http_cache.get(method, url, headers)).to eq(response_data)

      # Delete it
      http_cache.delete(method, url, headers)

      # Verify it's gone
      expect(http_cache.get(method, url, headers)).to be_nil
    end

    it "handles missing entries gracefully" do
      expect { http_cache.delete(method, url, headers) }.not_to raise_error
    end
  end

  describe "#clear" do
    it "clears all cached entries" do
      # Cache multiple responses
      http_cache.set("GET", "http://example.com/api1", {}, {
                       status_code: 200, headers: {}, body: "data1"
                     })
      http_cache.set("GET", "http://example.com/api2", {}, {
                       status_code: 200, headers: {}, body: "data2"
                     })

      # Clear cache
      http_cache.clear

      # Verify entries are gone
      expect(http_cache.get("GET", "http://example.com/api1", {})).to be_nil
      expect(http_cache.get("GET", "http://example.com/api2", {})).to be_nil
    end
  end

  describe "#stats" do
    it "returns cache statistics" do
      stats = http_cache.stats

      expect(stats).to include(
        adapter_type: "memory",
        config: hash_including(
          default_ttl: 3600,
          max_entries: 10_000,
          respect_http_headers: true,
          enable_conditional_requests: true
        )
      )
    end
  end

  describe "vary header support" do
    let(:url) { "http://example.com/api" }
    let(:method) { "GET" }

    it "caches different responses for different vary headers" do
      pending "Vary-based caching requires multi-entry storage per URL key — not yet implemented"
      vary_response = {
        status_code: 200,
        headers: { "vary" => "Accept-Encoding", "content-type" => "application/json" },
        body: '{"compressed": false}'
      }

      gzip_response = {
        status_code: 200,
        headers: { "vary" => "Accept-Encoding", "content-type" => "application/json" },
        body: '{"compressed": true}'
      }

      # Cache response for no encoding
      result1 = http_cache.fetch(method, url, {}) { vary_response }
      expect(result1).to eq(vary_response)

      # Cache response for gzip encoding
      result2 = http_cache.fetch(method, url, { "accept-encoding" => "gzip" }) { gzip_response }
      expect(result2).to eq(gzip_response)

      # Verify both are cached separately
      cached1 = http_cache.get(method, url, {})
      cached2 = http_cache.get(method, url, { "accept-encoding" => "gzip" })

      expect(cached1[:body]).to eq('{"compressed": false}')
      expect(cached2[:body]).to eq('{"compressed": true}')
    end
  end

  describe "HTTP cache directives" do
    let(:url) { "http://example.com/api" }
    let(:method) { "GET" }
    let(:headers) { {} }

    it "forces revalidation for no-cache responses" do
      no_cache_response = {
        status_code: 200,
        headers: { "cache-control" => "no-cache", "etag" => '"nc1"' },
        body: "no-cache data"
      }

      http_cache.fetch(method, url, headers) { no_cache_response }

      revalidated = false
      http_cache.fetch(method, url, headers) do |req_headers|
        revalidated = true
        expect(req_headers["If-None-Match"]).to eq('"nc1"')
        { status_code: 304, headers: {}, body: "" }
      end

      expect(revalidated).to be true
    end

    it "handles must-revalidate by revalidating stale entries" do
      response = {
        status_code: 200,
        headers: { "cache-control" => "max-age=1, must-revalidate", "etag" => '"mr1"' },
        body: "revalidate data"
      }

      http_cache.fetch(method, url, headers) { response }
      sleep(1.1)

      revalidated = false
      http_cache.fetch(method, url, headers) do |req_headers|
        revalidated = true
        expect(req_headers["If-None-Match"]).to eq('"mr1"')
        { status_code: 304, headers: {}, body: "" }
      end

      expect(revalidated).to be true
    end

    it "handles malformed cache-control headers gracefully" do
      malformed_response = {
        status_code: 200,
        headers: { "cache-control" => "invalid-directive", "expires" => "not-a-date" },
        body: "malformed data"
      }

      result = http_cache.fetch(method, url, headers) { malformed_response }
      expect(result[:body]).to eq("malformed data")

      # Should still be cacheable (falls through to default TTL)
      cached = http_cache.get(method, url, headers)
      expect(cached).not_to be_nil
    end
  end

  describe "filesystem adapter" do
    let(:method) { "GET" }
    let(:headers) { {} }
    let(:response_data) do
      {
        status_code: 200,
        headers: { "cache-control" => "max-age=3600" },
        body: "fs data"
      }
    end

    it "caches responses to disk" do
      Dir.mktmpdir do |tmpdir|
        fs_cache = described_class.new(
          adapter_type: "filesystem",
          default_ttl: 3600,
          adapter_options: { path: tmpdir }
        )

        fs_cache.set(method, "http://example.com/fs-test", headers, response_data)

        # Verify cache file was created
        cache_files = Dir.glob(File.join(tmpdir, "**", "*")).select { |f| File.file?(f) }
        expect(cache_files).not_to be_empty

        cached = fs_cache.get(method, "http://example.com/fs-test", headers)
        expect(cached[:body]).to eq("fs data")
      end
    end
  end

  describe "query parameter handling" do
    let(:method) { "GET" }
    let(:headers) { {} }
    let(:response_data) do
      {
        status_code: 200,
        headers: {},
        body: "data"
      }
    end

    it "normalizes query parameter order" do
      url1 = "http://example.com/api?b=2&a=1"
      url2 = "http://example.com/api?a=1&b=2"

      # Cache response for first URL
      http_cache.set(method, url1, headers, response_data)

      # Second URL should hit cache (same normalized key)
      cached = http_cache.get(method, url2, headers)
      expect(cached).to eq(response_data)
    end

    context "with ignored parameters" do
      let(:cache_config_with_ignored_params) do
        {
          adapter_type: "memory",
          default_ttl: 3600,
          ignore_query_params: %w[timestamp nonce]
        }
      end

      let(:http_cache) { described_class.new(cache_config_with_ignored_params) }

      it "ignores specified query parameters" do
        url1 = "http://example.com/api?data=value&timestamp=123"
        url2 = "http://example.com/api?data=value&timestamp=456"

        # Cache response for first URL
        http_cache.set(method, url1, headers, response_data)

        # Second URL should hit cache (timestamp ignored)
        cached = http_cache.get(method, url2, headers)
        expect(cached).to eq(response_data)
      end
    end
  end
end
