require "lutaml/model"
require "time"
require "digest"

module Lutaml
  module Store
    class HttpCacheEntry
      include Lutaml::Model::Serialize

      attribute :cache_key, :string
      attribute :url, :string
      attribute :method, :string, default: "GET"
      attribute :request_headers, :hash, default: {}
      attribute :response_body, :string
      attribute :response_headers, :hash, default: {}
      attribute :status_code, :integer
      attribute :cached_at, :time
      attribute :etag, :string
      attribute :last_modified, :time
      attribute :expires_at, :time
      attribute :max_age, :integer
      attribute :cache_control, :hash, default: {}
      attribute :vary_headers, :string, collection: true, default: []

      def fresh?
        return false if expired?
        return false if must_revalidate?

        true
      end

      def expired?
        return true if expires_at && Time.now > expires_at
        return true if max_age && (Time.now - cached_at) > max_age

        false
      end

      def must_revalidate?
        !!(cache_control["must-revalidate"] || cache_control["no-cache"])
      end

      def stale?
        !fresh?
      end

      def cacheable?
        return false if status_code < 200 || status_code >= 400
        return false if cache_control["no-store"]
        return false if cache_control["private"]

        true
      end

      def age
        Time.now - cached_at
      end

      def remaining_ttl
        return 0 if expired?
        return Float::INFINITY unless expires_at

        expires_at - Time.now
      end
    end
  end
end
