# frozen_string_literal: true

module Lutaml
  module Store
    module Adapter
      autoload :Base, "lutaml/store/adapter/base"
      autoload :Memory, "lutaml/store/adapter/memory"
      autoload :FileSystem, "lutaml/store/adapter/filesystem"
      autoload :Sqlite, "lutaml/store/adapter/sqlite"
    end
  end
end
