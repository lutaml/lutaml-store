# frozen_string_literal: true

# The backend configures lutaml-model's adapter registry at activation,
# so the model namespace and its adapter autoloads must be loaded even
# when the store is required standalone (rake tasks do).
require "lutaml/model"

module Lutaml
  module Store
    # Model YAML engine selection for serialization formats backed by
    # lutaml-model. The yeptris engine (native loader, measured 4x
    # faster than Psych on large documents) activates only when
    # explicitly enabled with FONTIST_YAML=yeptris, sharing the switch
    # with fontist. It stays off by default because the yeptris
    # x86_64-linux and Windows builds currently mis-parse some plain
    # scalars as single-element Arrays (leptris/yeptris#863); flip the
    # default once that parity fix lands.
    module YamlBackend
      ENV_KEY = "FONTIST_YAML"
      ENABLED_VALUE = "yeptris"

      class << self
        def activate!
          return nil unless ENV[ENV_KEY] == ENABLED_VALUE
          return nil unless yeptris_available?

          adapter = Class.new(Lutaml::Yaml::Adapter::StandardAdapter) do
            def self.parse(yaml, _options = {})
              Yeptris::YAML.load(yaml)
            end
          end

          Lutaml::Model::AdapterResolver.set_adapter_class(:yaml, adapter)

          adapter
        end

        def yeptris_available?
          require "yeptris"
          true
        rescue LoadError
          false
        end
      end
    end
  end
end
