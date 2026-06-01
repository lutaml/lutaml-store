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

  spec.bindir = "exe"
  spec.require_paths = ["lib"]
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|features)/})
    end
  end
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.add_dependency "lutaml-model", "~> 0.8.15"

  spec.metadata["rubygems_mfa_required"] = "true"
end
