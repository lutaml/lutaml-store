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

module Lutaml
  module Store
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class BackendError < Error; end
  end
end
