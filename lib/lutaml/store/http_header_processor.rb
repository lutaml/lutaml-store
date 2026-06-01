# frozen_string_literal: true

require "uri"
require "digest"
require "time"

module Lutaml
  module Store
    class HttpHeaderProcessor
      # Parse Cache-Control header according to RFC 7234
      def self.parse_cache_control(header_value)
        return {} unless header_value

        directives = {}
        header_value.split(",").each do |directive|
          key, value = directive.strip.split("=", 2)
          key = key.strip.downcase

          if value
            # Handle quoted values
            value = value.strip.gsub(/^"(.*)"$/, '\1')
            directives[key] = value.match?(/^\d+$/) ? value.to_i : value
          else
            directives[key] = true
          end
        end
        directives
      end

      # Calculate expiry time based on HTTP headers
      def self.calculate_expiry(response_headers, cached_at, default_ttl)
        cache_control = parse_cache_control(response_headers["cache-control"])

        # Check for explicit expiry
        if (expires_header = response_headers["expires"])
          begin
            return Time.parse(expires_header)
          rescue StandardError
            nil
          end
        end

        # Check for max-age
        if (max_age = cache_control["max-age"])
          return cached_at + max_age
        end

        # Fall back to default TTL
        cached_at + default_ttl
      end

      # Determine if response should be cached
      def self.should_cache_response?(status_code, response_headers)
        return false if status_code < 200 || status_code >= 400

        cache_control = parse_cache_control(response_headers["cache-control"])
        return false if cache_control["no-store"]
        return false if cache_control["private"] # Unless explicitly allowing private

        true
      end

      # Generate cache key from request details
      def self.generate_cache_key(method, url, vary_headers = {}, ignore_params = [])
        uri = URI.parse(url)

        # Normalize query parameters
        if uri.query
          params = URI.decode_www_form(uri.query)
          # Filter out ignored parameters
          params = params.reject { |key, _| ignore_params.include?(key) }
          params = params.sort
          uri.query = params.empty? ? nil : URI.encode_www_form(params)
        end

        base_key = "#{method.upcase}:#{uri}"

        # Add vary headers to key if present
        if vary_headers.any?
          vary_suffix = vary_headers.sort.map { |k, v| "#{k}:#{v}" }.join("|")
          base_key += "|#{Digest::SHA256.hexdigest(vary_suffix)[0..8]}"
        end

        base_key
      end

      # Parse Vary header
      def self.parse_vary_header(vary_header)
        return [] unless vary_header

        vary_header.split(",").map(&:strip).map(&:downcase)
      end

      # Extract vary headers from request headers
      def self.extract_vary_headers(request_headers, vary_header_names)
        return {} if vary_header_names.empty?

        vary_headers = {}
        vary_header_names.each do |header_name|
          normalized_name = header_name.downcase
          # Find header with case-insensitive matching
          actual_header = request_headers.find { |k, _| k.downcase == normalized_name }
          vary_headers[normalized_name] = actual_header[1] if actual_header
        end
        vary_headers
      end

      # Check if response is fresh based on age
      def self.fresh?(cached_at, max_age, expires_at)
        return false if expires_at && Time.now > expires_at
        return false if max_age && (Time.now - cached_at) > max_age

        true
      end

      # Build conditional request headers
      def self.build_conditional_headers(cache_entry, original_headers)
        conditional_headers = original_headers.dup

        conditional_headers["If-None-Match"] = cache_entry.etag if cache_entry.etag

        conditional_headers["If-Modified-Since"] = cache_entry.last_modified.httpdate if cache_entry.last_modified

        conditional_headers
      end

      # Parse Last-Modified header
      def self.parse_last_modified(header_value)
        return nil unless header_value

        begin
          Time.parse(header_value)
        rescue StandardError
          nil
        end
      end

      # Check if cache entry matches request (considering Vary)
      def self.cache_entry_matches?(cache_entry, request_headers, config)
        return true if cache_entry.vary_headers.empty?

        # Extract vary headers from current request
        current_vary = extract_vary_headers(request_headers, cache_entry.vary_headers)

        # Compare with cached vary headers
        cache_entry.vary_headers.each do |header_name|
          cached_value = cache_entry.request_headers[header_name.downcase]
          current_value = current_vary[header_name.downcase]

          # Skip comparison for ignored headers
          next if config.should_ignore_vary_header?(header_name)

          return false if cached_value != current_value
        end

        true
      end

      # Normalize header name for consistent storage
      def self.normalize_header_name(name)
        name.to_s.downcase.strip
      end

      # Check if response has caching directives
      def self.has_caching_directives?(response_headers)
        return true if response_headers["cache-control"]
        return true if response_headers["expires"]
        return true if response_headers["etag"]
        return true if response_headers["last-modified"]

        false
      end
    end
  end
end
