# frozen_string_literal: true

module Lutaml
  module Store
    class HttpCache
      def initialize(config)
        @config = config.is_a?(HttpCacheConfig) ? config : HttpCacheConfig.new(config)
        @config.validate!
        @adapter = create_adapter
        @stats = {
          cache_hits: 0,
          cache_misses: 0,
          conditional_requests: 0,
          not_modified_responses: 0,
          entries_stored: 0,
          entries_evicted: 0
        }
      end

      # Main cache interface - fetch with block for cache miss
      def fetch(method, url, headers = {}, &block)
        raise ArgumentError, "Block required for cache miss handling" unless block_given?

        # Generate cache key considering vary headers
        vary_headers = extract_request_vary_headers(headers)
        cache_key = HttpHeaderProcessor.generate_cache_key(
          method,
          url,
          vary_headers,
          @config.ignore_query_params
        )

        prefixed_key = @config.cache_key_for(cache_key)
        entry = get_entry(prefixed_key)

        # Check if entry matches current request (Vary header consideration)
        if entry && cache_entry_matches?(entry, headers)
          if entry.fresh?
            @stats[:cache_hits] += 1
            return create_response_from_entry(entry)
          elsif entry.stale? && @config.enable_conditional_requests
            # Try conditional request
            @stats[:conditional_requests] += 1
            return handle_conditional_request(entry, headers, prefixed_key, &block)
          end
        end

        # Cache miss or unusable entry - make fresh request
        @stats[:cache_misses] += 1
        response = yield(headers)
        cache_response(prefixed_key, method, url, headers, response)
      end

      # Get cached entry without making requests
      def get(method, url, headers = {})
        vary_headers = extract_request_vary_headers(headers)
        cache_key = HttpHeaderProcessor.generate_cache_key(
          method,
          url,
          vary_headers,
          @config.ignore_query_params
        )

        prefixed_key = @config.cache_key_for(cache_key)
        entry = get_entry(prefixed_key)

        return nil unless entry
        return nil unless cache_entry_matches?(entry, headers)
        return nil unless entry.fresh?

        create_response_from_entry(entry)
      end

      # Store response in cache
      def set(method, url, headers, response)
        return response unless should_cache_response?(response)

        vary_headers = extract_request_vary_headers(headers)
        cache_key = HttpHeaderProcessor.generate_cache_key(
          method,
          url,
          vary_headers,
          @config.ignore_query_params
        )

        prefixed_key = @config.cache_key_for(cache_key)
        cache_response(prefixed_key, method, url, headers, response)
      end

      # Delete cached entry
      def delete(method, url, headers = {})
        vary_headers = extract_request_vary_headers(headers)
        cache_key = HttpHeaderProcessor.generate_cache_key(
          method,
          url,
          vary_headers,
          @config.ignore_query_params
        )

        prefixed_key = @config.cache_key_for(cache_key)
        @adapter.delete(prefixed_key)
      rescue StandardError
        # Log error but don't fail
        false
      end

      # Clear all cache entries
      def clear
        @adapter.clear
      rescue StandardError
        false
      end

      # Get cache statistics
      def stats
        total_requests = @stats[:cache_hits] + @stats[:cache_misses]
        hit_ratio = total_requests.positive? ? (@stats[:cache_hits].to_f / total_requests * 100) : 0

        {
          adapter_type: @config.adapter_type,
          total_entries: @adapter.size,
          cache_hits: @stats[:cache_hits],
          cache_misses: @stats[:cache_misses],
          conditional_requests: @stats[:conditional_requests],
          not_modified_responses: @stats[:not_modified_responses],
          entries_stored: @stats[:entries_stored],
          entries_evicted: @stats[:entries_evicted],
          hit_ratio: hit_ratio,
          total_requests: total_requests,
          config: {
            default_ttl: @config.default_ttl,
            max_entries: @config.max_entries,
            respect_http_headers: @config.respect_http_headers,
            enable_conditional_requests: @config.enable_conditional_requests
          }
        }
      end

      # Get all cache entries for inspection
      def all_entries
        entries = []
        @adapter.each_key do |key|
          data = @adapter.get(key)
          next unless data

          entries << HttpCacheEntry.from_json(data)
        rescue StandardError
          # Skip invalid entries
        end
        entries
      end

      private

      def create_adapter
        adapter_config = @config.to_adapter_config
        case adapter_config[:type]
        when :memory
          Adapter::Memory.new(adapter_config)
        when :filesystem
          Adapter::FileSystem.new(adapter_config)
        when :sqlite
          Adapter::Sqlite.new(adapter_config)
        else
          raise ArgumentError, "Unknown adapter type: #{adapter_config[:type]}"
        end
      end

      def get_entry(cache_key)
        data = @adapter.get(cache_key)
        return nil unless data

        HttpCacheEntry.from_json(data)
      rescue StandardError
        nil
      end

      def store_entry(cache_key, entry)
        @adapter.set(cache_key, entry.to_json)
      rescue StandardError
        false
      end

      def handle_conditional_request(entry, headers, cache_key, &block)
        # Build conditional headers
        conditional_headers = HttpHeaderProcessor.build_conditional_headers(entry, headers)
        response = yield(conditional_headers)

        if response[:status_code] == 304
          # Not modified - refresh cache timestamp and return cached content
          entry.cached_at = Time.now
          store_entry(cache_key, entry)
          create_response_from_entry(entry)
        else
          # Modified - cache new response
          cache_response(cache_key, entry.method, entry.url, headers, response)
        end
      end

      def cache_response(cache_key, method, url, request_headers, response)
        if should_cache_response?(response)
          entry = create_cache_entry(cache_key, method, url, request_headers, response)
          @stats[:entries_stored] += 1 if store_entry(cache_key, entry)
        end

        response
      end

      def should_cache_response?(response)
        return false unless @config.respect_http_headers
        return false unless response[:status_code]

        HttpHeaderProcessor.should_cache_response?(response[:status_code], response[:headers] || {})
      end

      def create_cache_entry(cache_key, method, url, request_headers, response)
        cached_at = Time.now
        response_headers = response[:headers] || {}

        # Parse cache control and calculate expiry
        cache_control = HttpHeaderProcessor.parse_cache_control(response_headers["cache-control"])
        expires_at = HttpHeaderProcessor.calculate_expiry(response_headers, cached_at, @config.default_ttl)

        # Parse vary headers
        vary_headers = HttpHeaderProcessor.parse_vary_header(response_headers["vary"])

        # Extract vary header values from request
        request_vary_headers = {}
        if vary_headers.any?
          request_vary_headers = HttpHeaderProcessor.extract_vary_headers(request_headers,
                                                                          vary_headers)
        end

        HttpCacheEntry.new(
          cache_key: cache_key,
          url: url,
          method: method,
          request_headers: request_vary_headers, # Store only vary-relevant headers
          response_body: response[:body] || "",
          response_headers: response_headers,
          status_code: response[:status_code],
          cached_at: cached_at,
          etag: response_headers["etag"],
          last_modified: HttpHeaderProcessor.parse_last_modified(response_headers["last-modified"]),
          expires_at: expires_at,
          max_age: cache_control["max-age"],
          cache_control: cache_control,
          vary_headers: vary_headers
        )
      end

      def create_response_from_entry(entry)
        {
          status_code: entry.status_code,
          headers: entry.response_headers,
          body: entry.response_body
        }
      end

      def extract_request_vary_headers(_headers)
        # For now, return empty hash - will be populated when we know vary headers
        {}
      end

      def cache_entry_matches?(entry, request_headers)
        return true if entry.vary_headers.empty?

        HttpHeaderProcessor.cache_entry_matches?(entry, request_headers, @config)
      end
    end
  end
end
