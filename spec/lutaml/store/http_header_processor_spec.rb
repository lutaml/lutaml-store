# frozen_string_literal: true

require "spec_helper"
require "lutaml/store/http_header_processor"

RSpec.describe Lutaml::Store::HttpHeaderProcessor do
  describe ".parse_cache_control" do
    it "parses simple directives" do
      result = described_class.parse_cache_control("no-cache, no-store")
      expect(result).to eq({
                             "no-cache" => true,
                             "no-store" => true
                           })
    end

    it "parses directives with values" do
      result = described_class.parse_cache_control("max-age=3600, s-maxage=7200")
      expect(result).to eq({
                             "max-age" => 3600,
                             "s-maxage" => 7200
                           })
    end

    it "parses quoted values" do
      result = described_class.parse_cache_control('max-age="3600", custom="value"')
      expect(result).to eq({
                             "max-age" => 3600,
                             "custom" => "value"
                           })
    end

    it "handles nil input" do
      result = described_class.parse_cache_control(nil)
      expect(result).to eq({})
    end

    it "handles empty string" do
      result = described_class.parse_cache_control("")
      expect(result).to eq({})
    end
  end

  describe ".calculate_expiry" do
    let(:cached_at) { Time.now }
    let(:default_ttl) { 3600 }

    context "with Expires header" do
      it "uses Expires header when present" do
        expires_time = Time.now + 7200
        headers = { "expires" => expires_time.httpdate }

        result = described_class.calculate_expiry(headers, cached_at, default_ttl)
        expect(result).to be_within(1).of(expires_time)
      end

      it "handles invalid Expires header gracefully" do
        headers = { "expires" => "invalid-date" }

        result = described_class.calculate_expiry(headers, cached_at, default_ttl)
        expect(result).to be_within(1).of(cached_at + default_ttl)
      end
    end

    context "with Cache-Control max-age" do
      it "uses max-age when present" do
        headers = { "cache-control" => "max-age=7200" }

        result = described_class.calculate_expiry(headers, cached_at, default_ttl)
        expect(result).to be_within(1).of(cached_at + 7200)
      end
    end

    context "with no caching headers" do
      it "falls back to default TTL" do
        headers = {}

        result = described_class.calculate_expiry(headers, cached_at, default_ttl)
        expect(result).to be_within(1).of(cached_at + default_ttl)
      end
    end
  end

  describe ".should_cache_response?" do
    it "caches successful responses" do
      result = described_class.should_cache_response?(200, {})
      expect(result).to be true
    end

    it "does not cache error responses" do
      result = described_class.should_cache_response?(404, {})
      expect(result).to be false
    end

    it "does not cache responses with no-store" do
      headers = { "cache-control" => "no-store" }
      result = described_class.should_cache_response?(200, headers)
      expect(result).to be false
    end

    it "does not cache private responses" do
      headers = { "cache-control" => "private" }
      result = described_class.should_cache_response?(200, headers)
      expect(result).to be false
    end
  end

  describe ".generate_cache_key" do
    it "generates basic cache key" do
      result = described_class.generate_cache_key("GET", "http://example.com/api")
      expect(result).to eq("GET:http://example.com/api")
    end

    it "normalizes query parameters" do
      result = described_class.generate_cache_key("GET", "http://example.com/api?b=2&a=1")
      expect(result).to eq("GET:http://example.com/api?a=1&b=2")
    end

    it "filters ignored parameters" do
      result = described_class.generate_cache_key(
        "GET",
        "http://example.com/api?timestamp=123&data=value",
        {},
        ["timestamp"]
      )
      expect(result).to eq("GET:http://example.com/api?data=value")
    end

    it "includes vary headers in key" do
      vary_headers = { "accept-encoding" => "gzip", "accept-language" => "en" }
      result = described_class.generate_cache_key("GET", "http://example.com/api", vary_headers)

      expect(result).to start_with("GET:http://example.com/api|")
      expect(result).to include(Digest::SHA256.hexdigest("accept-encoding:gzip|accept-language:en")[0..8])
    end
  end

  describe ".parse_vary_header" do
    it "parses single header" do
      result = described_class.parse_vary_header("Accept-Encoding")
      expect(result).to eq(["accept-encoding"])
    end

    it "parses multiple headers" do
      result = described_class.parse_vary_header("Accept-Encoding, Accept-Language, User-Agent")
      expect(result).to eq(%w[accept-encoding accept-language user-agent])
    end

    it "handles nil input" do
      result = described_class.parse_vary_header(nil)
      expect(result).to eq([])
    end
  end

  describe ".extract_vary_headers" do
    let(:request_headers) do
      {
        "Accept-Encoding" => "gzip, deflate",
        "Accept-Language" => "en-US,en;q=0.9",
        "User-Agent" => "Mozilla/5.0"
      }
    end

    it "extracts specified headers" do
      vary_names = %w[accept-encoding accept-language]
      result = described_class.extract_vary_headers(request_headers, vary_names)

      expect(result).to eq({
                             "accept-encoding" => "gzip, deflate",
                             "accept-language" => "en-US,en;q=0.9"
                           })
    end

    it "handles case-insensitive matching" do
      vary_names = ["ACCEPT-ENCODING"]
      result = described_class.extract_vary_headers(request_headers, vary_names)

      expect(result).to eq({
                             "accept-encoding" => "gzip, deflate"
                           })
    end

    it "returns empty hash for empty vary names" do
      result = described_class.extract_vary_headers(request_headers, [])
      expect(result).to eq({})
    end
  end

  describe ".fresh?" do
    let(:cached_at) { Time.now - 1800 } # 30 minutes ago

    it "returns true when not expired" do
      expires_at = Time.now + 1800 # 30 minutes from now
      result = described_class.fresh?(cached_at, 3600, expires_at)
      expect(result).to be true
    end

    it "returns false when expires_at is past" do
      expires_at = Time.now - 100
      result = described_class.fresh?(cached_at, 3600, expires_at)
      expect(result).to be false
    end

    it "returns false when max_age is exceeded" do
      result = described_class.fresh?(cached_at, 1000, nil) # max_age less than age
      expect(result).to be false
    end
  end

  describe ".build_conditional_headers" do
    let(:cache_entry) do
      double(
        etag: '"abc123"',
        last_modified: Time.parse("2023-01-01 12:00:00 UTC")
      )
    end

    it "adds If-None-Match for ETag" do
      original_headers = { "accept" => "application/json" }
      result = described_class.build_conditional_headers(cache_entry, original_headers)

      expect(result["If-None-Match"]).to eq('"abc123"')
      expect(result["accept"]).to eq("application/json")
    end

    it "adds If-Modified-Since for Last-Modified" do
      original_headers = { "accept" => "application/json" }
      result = described_class.build_conditional_headers(cache_entry, original_headers)

      expect(result["If-Modified-Since"]).to eq("Sun, 01 Jan 2023 12:00:00 GMT")
    end

    it "handles missing ETag and Last-Modified" do
      cache_entry_without_headers = double(etag: nil, last_modified: nil)
      original_headers = { "accept" => "application/json" }

      result = described_class.build_conditional_headers(cache_entry_without_headers, original_headers)

      expect(result["If-None-Match"]).to be_nil
      expect(result["If-Modified-Since"]).to be_nil
      expect(result["accept"]).to eq("application/json")
    end
  end

  describe ".parse_last_modified" do
    it "parses valid date" do
      date_string = "Sun, 01 Jan 2023 12:00:00 GMT"
      result = described_class.parse_last_modified(date_string)

      expect(result).to be_a(Time)
      expect(result.year).to eq(2023)
    end

    it "handles invalid date gracefully" do
      result = described_class.parse_last_modified("invalid-date")
      expect(result).to be_nil
    end

    it "handles nil input" do
      result = described_class.parse_last_modified(nil)
      expect(result).to be_nil
    end
  end

  describe ".has_caching_directives?" do
    it "returns true for Cache-Control header" do
      headers = { "cache-control" => "max-age=3600" }
      expect(described_class.has_caching_directives?(headers)).to be true
    end

    it "returns true for Expires header" do
      headers = { "expires" => "Sun, 01 Jan 2024 12:00:00 GMT" }
      expect(described_class.has_caching_directives?(headers)).to be true
    end

    it "returns true for ETag header" do
      headers = { "etag" => '"abc123"' }
      expect(described_class.has_caching_directives?(headers)).to be true
    end

    it "returns true for Last-Modified header" do
      headers = { "last-modified" => "Sun, 01 Jan 2023 12:00:00 GMT" }
      expect(described_class.has_caching_directives?(headers)).to be true
    end

    it "returns false for no caching headers" do
      headers = { "content-type" => "application/json" }
      expect(described_class.has_caching_directives?(headers)).to be false
    end
  end
end
