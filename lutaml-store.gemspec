# frozen_string_literal: true

require_relative "lib/lutaml/store/version"

Gem::Specification.new do |spec|
  spec.name = "lutaml-store"
  spec.version = Lutaml::Store::VERSION
  spec.authors = ["Ronald Tse"]
  spec.email = ["ronald.tse@ribose.com"]

  spec.summary = "Store-centric database-style API for Lutaml::Model with multi-backend persistence."
  spec.description = <<~DESCRIPTION
    Provides a unified store interface for Lutaml::Model objects with model registry,
    polymorphic support, composite relationships, and multiple storage backends
    (memory, filesystem, SQLite).
  DESCRIPTION

  spec.homepage = "https://github.com/lutaml/lutaml-store"
  spec.license = "BSD-2-Clause"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__,
                                             err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github
                          Gemfile demo/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.0.0"

  spec.add_dependency "lutaml-model", "~> 0.8.15"
  spec.add_dependency "rubyzip", "~> 2.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
end
