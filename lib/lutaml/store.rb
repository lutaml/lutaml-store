# frozen_string_literal: true

module Lutaml
  module Store
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class BackendError < Error; end
    class ModelNotRegisteredError < Error; end
    class InvalidKeyError < Error; end
    class PolymorphicUpdateError < Error; end
    class CompositeModelError < Error; end

    autoload :VERSION, "lutaml/store/version"
    autoload :Config, "lutaml/store/config"
    autoload :Cache, "lutaml/store/cache"
    autoload :Monitor, "lutaml/store/monitor"
    autoload :Events, "lutaml/store/events"
    autoload :Integrity, "lutaml/store/integrity"
    autoload :Compression, "lutaml/store/compression"
    autoload :BasicStore, "lutaml/store/basic_store"
    autoload :CacheStore, "lutaml/store/cache_store"
    autoload :ModelSerializer, "lutaml/store/model_serializer"
    autoload :ModelRegistration, "lutaml/store/model_registration"
    autoload :ModelRegistry, "lutaml/store/model_registry"
    autoload :CompositeModelHandler, "lutaml/store/composite_model_handler"
    autoload :AttributeUpdater, "lutaml/store/attribute_updater"
    autoload :DatabaseStore, "lutaml/store/database_store"
    autoload :FormatSerializer, "lutaml/store/format_serializer"
    autoload :PackageDefinition, "lutaml/store/package_definition"
    autoload :PackageStore, "lutaml/store/package_store"
    autoload :PackageTransport, "lutaml/store/package_transport"
    autoload :Adapter, "lutaml/store/adapter"
    autoload :StorageKey, "lutaml/store/storage_key"
    autoload :Format, "lutaml/store/format"
    autoload :Query, "lutaml/store/query"
    autoload :Predicate, "lutaml/store/predicate"

    autoload :HttpCache, "lutaml/store/http_cache"
    autoload :HttpCacheConfig, "lutaml/store/http_cache_config"
    autoload :HttpCacheEntry, "lutaml/store/http_cache_entry"
    autoload :HttpHeaderProcessor, "lutaml/store/http_header_processor"

    def self.new(adapter:, models: [], **options)
      DatabaseStore.new(adapter: adapter, models: models, **options)
    end
  end
end
