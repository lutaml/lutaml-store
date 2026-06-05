# frozen_string_literal: true

module Lutaml
  module Store
    module Adapter
      autoload :Base, "lutaml/store/adapter/base"
      autoload :Memory, "lutaml/store/adapter/memory"
      autoload :FileSystem, "lutaml/store/adapter/filesystem"
      autoload :Sqlite, "lutaml/store/adapter/sqlite"

      @registry = {
        memory: "Memory",
        filesystem: "FileSystem",
        sqlite: "Sqlite"
      }

      def self.resolve(type, options = {})
        entry = @registry[type.to_sym]
        raise ConfigurationError, "Unknown adapter type: #{type}" unless entry

        const_get(entry).new(options)
      end

      def self.register(type, adapter_class)
        @registry[type.to_sym] = adapter_class.name
      end
    end
  end
end
