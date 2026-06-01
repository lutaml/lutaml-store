# frozen_string_literal: true

require "lutaml/model"

module Lutaml
  module Store
    class HttpCacheConfig
      include Lutaml::Model::Serialize

      attribute :adapter_type, :string, default: "filesystem"
      attribute :adapter_options, :hash, default: {}
      attribute :default_ttl, :integer, default: 3600
      attribute :max_entries, :integer, default: 10_000
      attribute :respect_http_headers, :boolean, default: true
      attribute :enable_conditional_requests, :boolean, default: true
      attribute :enable_compression, :boolean, default: false
      attribute :cache_private_responses, :boolean, default: false
      attribute :ignore_query_params, :string, collection: true, default: []
      attribute :vary_ignore_headers, :string, collection: true, default: []
      attribute :cache_key_prefix, :string, default: "http_cache"

      def to_adapter_config
        base_config = {
          type: adapter_type.to_sym,
          **adapter_options.transform_keys(&:to_sym)
        }

        # Add compression if enabled
        base_config[:compression] = true if enable_compression

        base_config
      end

      def cache_key_for(key)
        "#{cache_key_prefix}:#{key}"
      end

      def should_ignore_query_param?(param)
        ignore_query_params.include?(param.to_s)
      end

      def should_ignore_vary_header?(header)
        vary_ignore_headers.map(&:downcase).include?(header.to_s.downcase)
      end

      def validate!
        raise ArgumentError, "default_ttl must be positive" if default_ttl <= 0
        raise ArgumentError, "max_entries must be positive" if max_entries <= 0
        raise ArgumentError, "adapter_type cannot be empty" if adapter_type.nil? || adapter_type.empty?
      end
    end
  end
end
