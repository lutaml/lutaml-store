# frozen_string_literal: true

module Lutaml
  module Store
    module PackageTransport
      autoload :Base, "lutaml/store/package_transport/base"
      autoload :DirectoryTransport, "lutaml/store/package_transport/directory_transport"
      autoload :ZipTransport, "lutaml/store/package_transport/zip_transport"

      TRANSPORTS = {
        directory: "DirectoryTransport",
        zip: "ZipTransport"
      }.freeze

      def self.resolve(transport)
        entry = TRANSPORTS[transport.to_sym]
        raise ConfigurationError, "Unknown transport: #{transport}" unless entry

        const_get(entry).new
      end
    end
  end
end
