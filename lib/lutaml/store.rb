# frozen_string_literal: true

require_relative "store/version"
require_relative "store/config"
require_relative "store/events"
require_relative "store/cache"
require_relative "store/monitor"
require_relative "store/adapter/base"
require_relative "store/adapter/filesystem"
require_relative "store/adapter/memory"
require_relative "store/adapter/sqlite"
require_relative "store/serializer"
require_relative "store/compression"
require_relative "store/integrity"
require_relative "store/store"
require_relative "store/cache_store"
require_relative "store/model_store"
require_relative "store/database_store"
require_relative "store/http_cache_entry"
require_relative "store/http_cache_config"
require_relative "store/http_header_processor"
require_relative "store/http_cache"
require_relative "store/cache_inspector"
require_relative "store/model_registration"
require_relative "store/model_registry"
require_relative "store/composite_model_handler"
require_relative "store/attribute_updater"

module Lutaml
  module Store
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class BackendError < Error; end
    class ModelNotRegisteredError < Error; end
    class InvalidKeyError < Error; end
    class PolymorphicUpdateError < Error; end
    class CompositeModelError < Error; end

    # New store-centric API entry point
    def self.new(adapter:, models: [], **options)
      DatabaseStore.new(adapter: adapter, models: models, **options)
    end
  end
end
