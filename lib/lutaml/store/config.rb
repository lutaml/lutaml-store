# frozen_string_literal: true

require "yaml"

module Lutaml
  module Store
    class Config
      DEFAULT_CONFIG = {
        "adapter" => {
          "type" => "memory",
          "options" => {}
        },
        "cache" => {
          "enabled" => true,
          "max_size" => 1000,
          "ttl" => nil
        },
        "monitoring" => {
          "enabled" => false
        },
        "events" => {
          "async" => false
        },
        "serialization" => {
          "formats" => ["marshal", "hash", "json", "yaml", "xml", "toml"],
          "validate_on_write" => false
        },
        "compression" => {
          "enabled" => false,
          "algorithm" => "gzip",
          "level" => 6
        }
      }.freeze

      attr_reader :adapter_type, :adapter_options, :cache_config,
                  :monitoring_config, :events_config, :serialization_config,
                  :compression_config

      def initialize(config = {})
        @config = merge_with_defaults(config)
        parse_config
      end

      # Load configuration from YAML file
      # @param file_path [String] path to YAML configuration file
      # @return [Config] new configuration instance
      def self.from_file(file_path)
        config_data = YAML.load_file(file_path)
        lutaml_config = config_data["lutaml_store"] || config_data
        new(lutaml_config)
      rescue Errno::ENOENT
        raise ConfigurationError, "Configuration file not found: #{file_path}"
      rescue Psych::SyntaxError => e
        raise ConfigurationError, "Invalid YAML in configuration file: #{e.message}"
      end

      # Load configuration from YAML string
      # @param yaml_string [String] YAML configuration as string
      # @return [Config] new configuration instance
      def self.from_yaml(yaml_string)
        config_data = YAML.safe_load(yaml_string)
        lutaml_config = config_data["lutaml_store"] || config_data
        new(lutaml_config)
      rescue Psych::SyntaxError => e
        raise ConfigurationError, "Invalid YAML configuration: #{e.message}"
      end

      # Check if caching is enabled
      # @return [Boolean] true if caching is enabled
      def cache_enabled?
        @cache_config[:enabled]
      end

      # Check if monitoring is enabled
      # @return [Boolean] true if monitoring is enabled
      def monitoring_enabled?
        @monitoring_config[:enabled]
      end

      # Check if async events are enabled
      # @return [Boolean] true if async events are enabled
      def async_events?
        @events_config[:async]
      end

      # Get cache TTL in seconds
      # @return [Integer, nil] TTL in seconds or nil for no expiration
      def cache_ttl
        @cache_config[:ttl]
      end

      # Get cache maximum size
      # @return [Integer] maximum number of items in cache
      def cache_max_size
        @cache_config[:max_size]
      end

      # Check if validation on write is enabled
      # @return [Boolean] true if validation on write is enabled
      def validate_on_write?
        @serialization_config[:validate_on_write]
      end

      # Get supported serialization formats
      # @return [Array<String>] list of supported formats
      def serialization_formats
        @serialization_config[:formats]
      end

      # Check if compression is enabled
      # @return [Boolean] true if compression is enabled
      def compression_enabled?
        @compression_config[:enabled]
      end

      # Get compression algorithm
      # @return [String] compression algorithm name
      def compression_algorithm
        @compression_config[:algorithm]
      end

      # Get compression level
      # @return [Integer] compression level (0-9)
      def compression_level
        @compression_config[:level]
      end

      # Validate the configuration
      # @raise [ConfigurationError] if configuration is invalid
      def validate!
        validate_adapter_config
        validate_cache_config
        validate_monitoring_config
        validate_events_config
      end

      # Convert configuration to hash
      # @return [Hash] configuration as hash
      def to_h
        {
          adapter: {
            type: @adapter_type,
            options: @adapter_options
          },
          cache: @cache_config,
          monitoring: @monitoring_config,
          events: @events_config
        }
      end

      private

      def merge_with_defaults(config)
        deep_merge(DEFAULT_CONFIG, stringify_keys(config))
      end

      def parse_config
        adapter_config = @config["adapter"]
        @adapter_type = adapter_config["type"].to_sym
        @adapter_options = symbolize_keys(adapter_config["options"] || {})

        @cache_config = symbolize_keys(@config["cache"])
        @monitoring_config = symbolize_keys(@config["monitoring"])
        @events_config = symbolize_keys(@config["events"])
        @serialization_config = symbolize_keys(@config["serialization"])
        @compression_config = symbolize_keys(@config["compression"])
      end

      def validate_adapter_config
        valid_adapters = %i[memory filesystem sqlite]
        unless valid_adapters.include?(@adapter_type)
          raise ConfigurationError,
                "Invalid adapter type: #{@adapter_type}. " \
                "Valid types: #{valid_adapters.join(', ')}"
        end

        case @adapter_type
        when :filesystem
          unless @adapter_options[:path]
            raise ConfigurationError, "FileSystem adapter requires 'path' option"
          end
        when :sqlite
          unless @adapter_options[:path]
            raise ConfigurationError, "SQLite adapter requires 'path' option"
          end
        end
      end

      def validate_cache_config
        if @cache_config[:max_size] && @cache_config[:max_size] <= 0
          raise ConfigurationError, "Cache max_size must be positive"
        end

        if @cache_config[:ttl] && @cache_config[:ttl] <= 0
          raise ConfigurationError, "Cache TTL must be positive"
        end
      end

      def validate_monitoring_config
        unless [true, false].include?(@monitoring_config[:enabled])
          raise ConfigurationError, "Monitoring enabled must be boolean"
        end
      end

      def validate_events_config
        unless [true, false].include?(@events_config[:async])
          raise ConfigurationError, "Events async must be boolean"
        end
      end

      def deep_merge(hash1, hash2)
        result = hash1.dup
        hash2.each do |key, value|
          if result[key].is_a?(Hash) && value.is_a?(Hash)
            result[key] = deep_merge(result[key], value)
          else
            result[key] = value
          end
        end
        result
      end

      def stringify_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          new_key = key.to_s
          new_value = value.is_a?(Hash) ? stringify_keys(value) : value
          result[new_key] = new_value
        end
      end

      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          new_key = key.to_sym
          new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
          result[new_key] = new_value
        end
      end
    end
  end
end
