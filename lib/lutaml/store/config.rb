# frozen_string_literal: true

require "yaml"

module Lutaml
  module Store
    class Config
      attr_reader :adapter_type, :adapter_options, :cache_enabled, :cache_max_size,
                  :cache_ttl, :monitoring_enabled, :async_events, :compression_enabled,
                  :compression_algorithm, :compression_level, :serialization_formats,
                  :validate_on_write

      def initialize(adapter_type: :memory, adapter_options: {},
                     cache: {}, monitoring: {}, events: {},
                     compression: {}, serialization: {}, **)
        @adapter_type = normalize_adapter_type(adapter_type)
        @adapter_options = symbolize_keys(adapter_options)

        cache_config = symbolize_keys(cache)
        @cache_enabled = cache_config.fetch(:enabled, true)
        @cache_max_size = cache_config.fetch(:max_size, 1000)
        @cache_ttl = cache_config.fetch(:ttl, nil)

        monitoring_config = symbolize_keys(monitoring)
        @monitoring_enabled = monitoring_config.fetch(:enabled, false)

        events_config = symbolize_keys(events)
        @async_events = events_config.fetch(:async, false)

        compression_config = symbolize_keys(compression)
        @compression_enabled = compression_config.fetch(:enabled, false)
        @compression_algorithm = compression_config.fetch(:algorithm, "gzip")
        @compression_level = compression_config.fetch(:level, 6)

        serialization_config = symbolize_keys(serialization)
        @serialization_formats = serialization_config.fetch(:formats, %w[marshal hash json yaml xml toml])
        @validate_on_write = serialization_config.fetch(:validate_on_write, false)
      end

      def self.from_file(file_path)
        config_data = YAML.load_file(file_path)
        lutaml_config = config_data["lutaml_store"] || config_data
        from_hash(lutaml_config)
      rescue Errno::ENOENT
        raise ConfigurationError, "Configuration file not found: #{file_path}"
      rescue Psych::SyntaxError => e
        raise ConfigurationError, "Invalid YAML in configuration file: #{e.message}"
      end

      def self.from_yaml(yaml_string)
        config_data = YAML.safe_load(yaml_string)
        lutaml_config = config_data["lutaml_store"] || config_data
        from_hash(lutaml_config)
      rescue Psych::SyntaxError => e
        raise ConfigurationError, "Invalid YAML configuration: #{e.message}"
      end

      def cache_enabled?
        @cache_enabled
      end

      def monitoring_enabled?
        @monitoring_enabled
      end

      def async_events?
        @async_events
      end

      def compression_enabled?
        @compression_enabled
      end

      def validate_on_write?
        @validate_on_write
      end

      def validate!
        validate_adapter_config
        validate_cache_config
        validate_monitoring_config
        validate_events_config
      end

      def to_h
        {
          adapter: { type: @adapter_type, options: @adapter_options },
          cache: { enabled: @cache_enabled, max_size: @cache_max_size, ttl: @cache_ttl },
          monitoring: { enabled: @monitoring_enabled },
          events: { async: @async_events },
          compression: { enabled: @compression_enabled, algorithm: @compression_algorithm, level: @compression_level },
          serialization: { formats: @serialization_formats, validate_on_write: @validate_on_write }
        }
      end

      class << self
        def from_hash(hash)
          symbolized = symbolize_keys(hash)
          adapter_config = symbolized[:adapter] || {}
          new(
            adapter_type: adapter_config[:type],
            adapter_options: adapter_config[:options] || {},
            cache: symbolized[:cache] || {},
            monitoring: symbolized[:monitoring] || {},
            events: symbolized[:events] || {},
            compression: symbolized[:compression] || {},
            serialization: symbolized[:serialization] || {}
          )
        end

        private :from_hash

        def symbolize_keys(hash)
          return hash unless hash.is_a?(Hash)

          hash.each_with_object({}) do |(key, value), result|
            new_key = key.to_sym
            new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
            result[new_key] = new_value
          end
        end
      end

      private

      def normalize_adapter_type(type)
        case type
        when Symbol then type
        when String then type.to_sym
        when Hash
          type[:type]&.to_sym || type["type"]&.to_sym || :memory
        else
          :memory
        end
      end

      def validate_adapter_config
        valid_adapters = %i[memory filesystem sqlite]
        unless valid_adapters.include?(@adapter_type)
          raise ConfigurationError,
                "Invalid adapter type: #{@adapter_type}. " \
                "Valid types: #{valid_adapters.join(", ")}"
        end

        case @adapter_type
        when :filesystem
          raise ConfigurationError, "FileSystem adapter requires 'path' option" unless @adapter_options[:path]
        when :sqlite
          raise ConfigurationError, "SQLite adapter requires 'path' option" unless @adapter_options[:path]
        end
      end

      def validate_cache_config
        raise ConfigurationError, "Cache max_size must be positive" if @cache_max_size && @cache_max_size <= 0

        return unless @cache_ttl && @cache_ttl <= 0

        raise ConfigurationError, "Cache TTL must be positive"
      end

      def validate_monitoring_config
        return if [true, false].include?(@monitoring_enabled)

        raise ConfigurationError, "Monitoring enabled must be boolean"
      end

      def validate_events_config
        return if [true, false].include?(@async_events)

        raise ConfigurationError, "Events async must be boolean"
      end

      def symbolize_keys(hash)
        self.class.symbolize_keys(hash)
      end
    end
  end
end
