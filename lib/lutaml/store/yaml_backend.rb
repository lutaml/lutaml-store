# frozen_string_literal: true

# The backend configures lutaml-model's adapter registry at activation,
# so the model namespace and its adapter autoloads must be loaded even
<<<<<<< HEAD
# when the store is required standalone (rake tasks do).
=======
# when the store itself is required standalone (rake tasks do).
>>>>>>> f3ca3d4 (Load lutaml-model before configuring its adapter registry)
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
        # lutaml-model auto-selects yeptris for a format whenever the
        # yeptris gem is in the bundle, which would silently switch
        # YAML parsing and dumping (and its line-wrap behavior) for
        # every model in the process. The adapter is therefore pinned
        # explicitly: yeptris when FONTIST_YAML=yeptris, the standard
        # Psych engine otherwise (the yeptris x86_64-linux and Windows
        # builds currently mis-parse some plain scalars as
        # single-element Arrays, leptris/yeptris#863).
        def activate!
          adapter = if ENV[ENV_KEY] == ENABLED_VALUE && yeptris_available?
                      Class.new(Lutaml::Yaml::Adapter::StandardAdapter) do
                        def self.parse(yaml, _options = {})
                          Yeptris::YAML.load(yaml)
                        end
                      end
                    else
                      Lutaml::Yaml::Adapter::StandardAdapter
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
