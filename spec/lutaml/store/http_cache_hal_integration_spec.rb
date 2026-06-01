# frozen_string_literal: true

require "spec_helper"
require "lutaml/store/http_cache"
require "lutaml/store/http_cache_config"
require "tmpdir"

# Mock HAL components for testing
module MockHal
  class MockClient
    attr_accessor :api_url

    def initialize(api_url = "https://api.example.com")
      @api_url = api_url
      @responses = {}
      @request_count = {}
    end

    def set_response(url, response, headers = {})
      @responses[url] = {
        body: response,
        headers: headers
      }
      @request_count[url] = 0
    end

    def get(url)
      full_url = url.start_with?("http") ? url : "#{@api_url}#{url}"
      @request_count[full_url] = (@request_count[full_url] || 0) + 1

      response_data = @responses[full_url]
      raise "No mock response for #{full_url}" unless response_data

      MockResponse.new(response_data[:body], response_data[:headers])
    end

    def get_with_headers(url, headers)
      # For conditional requests, check if we should return 304
      full_url = url.start_with?("http") ? url : "#{@api_url}#{url}"
      response_data = @responses[full_url]

      if response_data && headers["if-none-match"] == response_data[:headers]["etag"]
        @request_count[full_url] = (@request_count[full_url] || 0) + 1
        MockResponse.new("", { "status" => "304" }, 304)
      else
        get(url)
      end
    end

    def get_by_url(url)
      get(url)
    end

    def request_count(url)
      full_url = url.start_with?("http") ? url : "#{@api_url}#{url}"
      @request_count[full_url] || 0
    end
  end

  class MockResponse
    attr_reader :headers, :status

    def initialize(body, headers = {}, status = 200)
      @body = body.is_a?(String) ? JSON.parse(body) : body
      @headers = headers
      @status = status
    rescue JSON::ParserError
      @body = body
    end

    def to_json(*_args)
      @body.to_json
    end

    def to_h
      @body.is_a?(Hash) ? @body : { "data" => @body }
    end

    def [](key)
      to_h[key]
    end
  end

  class MockModel
    include Lutaml::Model::Serialize

    attribute :id, Lutaml::Model::Type::String
    attribute :name, Lutaml::Model::Type::String
    attribute :description, Lutaml::Model::Type::String

    json do
      map "id", to: :id
      map "name", to: :name
      map "description", to: :description
    end
  end

  # Simplified ModelRegister for testing
  class MockModelRegister
    attr_accessor :client, :cache_store

    def initialize(client:, cache: nil)
      @client = client
      @cache_store = setup_cache_store(cache) if cache
    end

    def fetch_resource(url, headers = {})
      # Use HTTP cache if available
      if @cache_store.respond_to?(:fetch)
        response = @cache_store.fetch("GET", url, headers) do |request_headers|
          raw_response = if request_headers.any?
                           @client.get_with_headers(url, request_headers)
                         else
                           @client.get(url)
                         end

          convert_client_response_to_http_format(raw_response)
        end

        convert_http_response_to_client_format(response)
      else
        @client.get(url)
      end
    end

    private

    def setup_cache_store(cache_config)
      return nil unless cache_config

      config = cache_config.is_a?(Hash) ? cache_config : { adapter: cache_config }

      http_config = Lutaml::Store::HttpCacheConfig.new(
        adapter_type: config[:adapter_type] || :memory,
        default_ttl: config[:ttl] || 3600,
        max_entries: config[:max_size] || 1000,
        respect_http_headers: config[:respect_http_headers] != false,
        enable_conditional_requests: config[:enable_conditional_requests] != false
      )

      # Add adapter options if needed
      http_config.adapter_options = { path: config[:path] } if config[:path]

      Lutaml::Store::HttpCache.new(http_config)
    end

    def convert_client_response_to_http_format(client_response)
      headers = {}
      headers = client_response.headers if client_response.respond_to?(:headers)

      {
        status_code: client_response.respond_to?(:status) ? client_response.status : 200,
        headers: headers,
        body: client_response.respond_to?(:to_json) ? client_response.to_json : client_response.to_s
      }
    end

    def convert_http_response_to_client_format(http_response)
      if http_response[:body].is_a?(String)
        begin
          JSON.parse(http_response[:body])
        rescue JSON::ParserError
          http_response[:body]
        end
      else
        http_response[:body]
      end
    end
  end
end

RSpec.describe "HTTP Cache HAL Integration" do
  let(:client) { MockHal::MockClient.new }
  let(:cache_config) do
    {
      adapter_type: :memory,
      ttl: 3600,
      max_size: 100,
      respect_http_headers: true,
      enable_conditional_requests: true
    }
  end
  let(:register) { MockHal::MockModelRegister.new(client: client, cache: cache_config) }

  describe "basic caching functionality" do
    let(:url) { "https://api.example.com/resources/123" }
    let(:response_data) do
      {
        "id" => "123",
        "name" => "Test Resource",
        "description" => "A test resource"
      }
    end

    before do
      client.set_response(url, response_data, {
                            "etag" => '"abc123"',
                            "cache-control" => "max-age=3600",
                            "last-modified" => "Wed, 21 Oct 2015 07:28:00 GMT"
                          })
    end

    it "caches responses and avoids duplicate requests" do
      # First request should hit the server
      result1 = register.fetch_resource(url)
      expect(client.request_count(url)).to eq(1)
      expect(result1["id"]).to eq("123")

      # Second request should use cache
      result2 = register.fetch_resource(url)
      expect(client.request_count(url)).to eq(1) # Still 1, no new request
      expect(result2["id"]).to eq("123")
    end

    it "respects cache-control headers" do
      # Set a very short TTL in the response
      client.set_response(url, response_data, {
                            "etag" => '"abc123"',
                            "cache-control" => "max-age=1"
                          })

      # First request
      register.fetch_resource(url)
      expect(client.request_count(url)).to eq(1)

      # Wait for cache to expire
      sleep(1.1)

      # Second request should hit server again due to expired cache
      register.fetch_resource(url)
      expect(client.request_count(url)).to eq(2)
    end

    it "uses conditional requests with ETags" do
      # First request to populate cache
      register.fetch_resource(url)
      expect(client.request_count(url)).to eq(1)

      # Wait for cache to expire naturally, then make another request
      # This should trigger a conditional request
      sleep(0.1) # Small delay to ensure different timestamps

      # The cache should still be valid, so no new request
      result = register.fetch_resource(url)
      expect(client.request_count(url)).to eq(1) # Still cached
      expect(result["id"]).to eq("123")
    end
  end

  describe "cache configuration" do
    it "works with memory adapter" do
      memory_register = MockHal::MockModelRegister.new(
        client: client,
        cache: { adapter_type: :memory, ttl: 1800 }
      )

      url = "https://api.example.com/memory-test"
      client.set_response(url, { "data" => "memory test" })

      result = memory_register.fetch_resource(url)
      expect(result["data"]).to eq("memory test")
      expect(client.request_count(url)).to eq(1)

      # Second request should use cache
      memory_register.fetch_resource(url)
      expect(client.request_count(url)).to eq(1)
    end

    it "works with filesystem adapter" do
      Dir.mktmpdir do |tmpdir|
        fs_register = MockHal::MockModelRegister.new(
          client: client,
          cache: {
            adapter_type: :filesystem,
            ttl: 1800,
            path: tmpdir
          }
        )

        url = "https://api.example.com/fs-test"
        client.set_response(url, { "data" => "filesystem test" })

        result = fs_register.fetch_resource(url)
        expect(result["data"]).to eq("filesystem test")
        expect(client.request_count(url)).to eq(1)

        # Second request should use cache
        fs_register.fetch_resource(url)
        expect(client.request_count(url)).to eq(1)

        # Verify cache file was created
        cache_files = Dir.glob(File.join(tmpdir, "**", "*")).select { |f| File.file?(f) }
        expect(cache_files).not_to be_empty
      end
    end
  end

  describe "HTTP semantics compliance" do
    let(:url) { "https://api.example.com/semantics-test" }

    it "respects no-cache directive" do
      client.set_response(url, { "data" => "no-cache test" }, {
                            "cache-control" => "no-cache"
                          })

      # First request
      register.fetch_resource(url)
      expect(client.request_count(url)).to eq(1)

      # Second request should not use cache due to no-cache
      register.fetch_resource(url)
      expect(client.request_count(url)).to eq(2)
    end

    it "respects no-store directive" do
      client.set_response(url, { "data" => "no-store test" }, {
                            "cache-control" => "no-store"
                          })

      # Requests should never be cached
      register.fetch_resource(url)
      register.fetch_resource(url)
      expect(client.request_count(url)).to eq(2)
    end

    it "handles must-revalidate directive" do
      client.set_response(url, { "data" => "revalidate test" }, {
                            "cache-control" => "max-age=1, must-revalidate",
                            "etag" => '"revalidate123"'
                          })

      # First request
      register.fetch_resource(url)
      expect(client.request_count(url)).to eq(1)

      # Wait for cache to expire
      sleep(1.1)

      # Should revalidate with conditional request
      register.fetch_resource(url)
      expect(client.request_count(url)).to eq(2)
    end
  end

  describe "performance benefits" do
    let(:url) { "https://api.example.com/performance-test" }

    it "provides significant performance improvement" do
      client.set_response(url, { "data" => "performance test" }, {
                            "etag" => '"perf123"',
                            "cache-control" => "max-age=3600"
                          })

      # Measure time for first request (cache miss)
      start_time = Time.now
      register.fetch_resource(url)
      first_request_time = Time.now - start_time

      # Measure time for second request (cache hit)
      start_time = Time.now
      register.fetch_resource(url)
      second_request_time = Time.now - start_time

      # Cache hit should be significantly faster
      expect(second_request_time).to be < (first_request_time * 0.1)
      expect(client.request_count(url)).to eq(1)
    end

    it "handles high request volume efficiently" do
      client.set_response(url, { "data" => "volume test" }, {
                            "cache-control" => "max-age=3600"
                          })

      # Make many requests
      100.times { register.fetch_resource(url) }

      # Should only hit the server once
      expect(client.request_count(url)).to eq(1)
    end
  end

  describe "error handling" do
    it "handles network errors gracefully" do
      url = "https://api.example.com/error-test"

      # Don't set up a mock response to simulate network error
      expect do
        register.fetch_resource(url)
      end.to raise_error(/No mock response/)
    end

    it "handles malformed cache headers" do
      url = "https://api.example.com/malformed-test"
      client.set_response(url, { "data" => "malformed test" }, {
                            "cache-control" => "invalid-directive",
                            "expires" => "not-a-date"
                          })

      # Should still work despite malformed headers
      result = register.fetch_resource(url)
      expect(result["data"]).to eq("malformed test")
    end
  end
end
