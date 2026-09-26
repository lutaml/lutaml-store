# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module Lutaml
  module Store
    module Source
      # Any static HTTP host — GitHub Pages, raw.githubusercontent, an
      # object-storage bucket. The consumer states the base URL; the source
      # appends one percent-encoded path segment per key.
      #
      # Every read may be wrapped in an explicit `cache:` (an
      # HttpCacheConfig hash) so ETag/304 revalidation is handled by the
      # store's HttpCache. With no cache configured, reads go straight to
      # the network — nothing is implied.
      #
      # `transport:` accepts a callable for tests and alternative HTTP
      # stacks: `->(uri, headers) { {status_code:, headers:, body:} }`.
      class Https < Base
        OPTIONS = %i[base_url].freeze

        RETRIED_ERRORS = [
          SocketError, Timeout::Error, IOError, SystemCallError,
          OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
          Net::ProtocolError
        ].freeze

        private

        def configure
          base = require_option(:base_url)
          @base = URI.parse(base.to_s)
          raise ConfigurationError, "base_url must be http(s)" unless @base.is_a?(URI::HTTP) ||
                                                                      @base.is_a?(URI::HTTPS)

          @headers = @options.fetch(:headers, {})
          @timeout = @options.fetch(:timeout, 60)
          @open_timeout = @options.fetch(:open_timeout, 60)
          @max_redirects = @options.fetch(:max_redirects, 3)
          @transport = @options[:transport]
          @cache = @options[:cache] && HttpCache.new(@options[:cache])
        end

        def fetch(uri, headers = {}, redirects = @max_redirects)
          response = raw_fetch(uri, headers)
          case response[:status_code]
          when 200..299 then response
          when 301, 302, 307, 308
            raise BackendError, "too many redirects fetching #{uri}" if redirects.zero?

            fetch(URI.parse(response[:headers]["location"]), headers, redirects - 1)
          when 404 then raise NotFoundError, "no entry at #{uri}"
          else raise BackendError, "HTTP #{response[:status_code]} fetching #{uri}"
          end
        end

        def raw_fetch(uri, headers)
          if @transport
            begin
              return @transport.call(uri, headers)
            rescue *RETRIED_ERRORS => e
              raise BackendError, "cannot fetch #{uri}: #{e.class}: #{e.message}"
            end
          end

          if @cache
            return @cache.fetch(:get, uri.to_s, headers) do |h|
              http_get(uri, h)
            end
          end

          http_get(uri, headers)
        end

        def http_get(uri, headers)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.is_a?(URI::HTTPS)
          http.open_timeout = @open_timeout
          http.read_timeout = @timeout
          begin
            resp = http.get(uri, @headers.merge(headers))
            { status_code: resp.code.to_i, headers: resp.each_header.to_h, body: resp.body }
          rescue *RETRIED_ERRORS => e
            raise BackendError, "cannot fetch #{uri}: #{e.class}: #{e.message}"
          end
        end

        def url_for(relative_path)
          base = @base.to_s.sub(%r{/+\z}, "")
          path = relative_path.sub(%r{\A/+}, "")
          URI.parse("#{base}/#{path}")
        end

        public

        def read(key)
          fetch(url_for(Source.encode_key(key)))[:body]
        end

        def manifest_raw
          fetch(url_for(@options.fetch(:manifest_path, "manifest.json")))[:body]
        end
      end
    end
  end
end
