# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & test commands

```sh
bin/setup             # Install dependencies
bundle exec rake      # Run specs + rubocop (default task)
bundle exec rspec     # Run all specs
bundle exec rspec spec/lutaml/store/basic_store_spec.rb  # Run a single spec file
bundle exec rubocop   # Lint
```

Ruby >= 3.1 required. CI uses Ruby 3.3.2.

## Architecture

This is a Ruby gem (`lutaml-store`) providing a store-centric database-style API for persisting LutaML Models across multiple storage backends.

### Two-layer store design

- **`Lutaml::Store.new(adapter:, models:)`** — the primary entry point. Returns a `DatabaseStore` instance with model registry support, CRUD operations (`save`, `fetch`, `update`, `destroy`), polymorphic model handling, composite model relationships, and dot-notation nested updates.

- **`Lutaml::Store::BasicStore`** — the low-level key-value store providing `get`, `set`, `delete`, `exists?`, `all`, `keys`, and bulk operations. Wraps an adapter with optional caching, monitoring, and event emission.

### Key classes in `lib/lutaml/store/`

| Class | Role |
|---|---|
| `DatabaseStore` | High-level CRUD with model registry, composite models, polymorphism, file I/O |
| `BasicStore` | Low-level key-value store with optional cache/monitor/events |
| `CacheStore` | TTL-aware cache store extending `BasicStore` |
| `PackageStore` | Structured multi-model packages with directory/ZIP transport |
| `PackageDefinition` | Declarative schema for package structure (models, assets, metadata) |
| `ModelRegistry` / `ModelRegistration` | Register models with their key fields and polymorphic config |
| `CompositeModelHandler` | Stores nested registered models independently, restores references |
| `AttributeUpdater` | Processes updates including dot-notation paths and block-based updates |
| `ModelSerializer` | Hash-based serialization/deserialization for key-value storage |
| `FormatSerializer` | Bridges any Format handler to ModelSerializer interface for DatabaseStore |
| `Format` | Multi-format file I/O (YAML, YAMLS, JSON, JSONL, Marshal, XML) |
| `Adapter` | Storage adapter registry and factory (Memory, FileSystem, SQLite) |

### Format handlers (`lib/lutaml/store/format/`)

All inherit from `Format::Base`. Six formats: `Yaml`, `Yamls`, `Json`, `Jsonl`, `MarshalFormat`, `Xml`. Each implements `serialize`/`deserialize`, optional `serialize_many`/`deserialize_many`, `extension`, `glob_pattern`, and `binary?`. Registered in `Format::FORMATS` hash and resolved via `Format.resolve(:symbol)`.

### Storage adapters (`lib/lutaml/store/adapter/`)

All inherit from `Adapter::Base`. Three backends: `Memory`, `FileSystem`, `SQLite`. Registered in `Adapter` module and resolved via `Adapter.resolve(:type, options)`. New adapters can be added with `Adapter.register(:custom, CustomClass)` without modifying existing code (OCP).

### PackageStore and transports

`PackageStore` provides structured multi-model persistence. `PackageDefinition` declares which models, assets, and metadata the package contains. Transports (`DirectoryTransport`, `ZipTransport`) handle reading/writing to disk. Format handlers determine serialization per model entry.

### FormatSerializer pattern

`FormatSerializer` wraps a Format handler to implement the serializer interface (serialize/deserialize). This enables `DatabaseStore` to use any format (YAMLS, XML, Marshal, etc.) for key-value storage instead of the default hash serialization. Used for Glossarist-like YAMLS patterns.

### HTTP caching

`HttpCache` provides HTTP-aware caching with ETags, conditional requests (304), Cache-Control, and Vary header support. Uses `to_json`/`from_json` for model-driven serialization.

## Conventions

- Double-quoted strings (Rubocop enforced)
- Specs use `expect` syntax (no `should`)
- Documentation is in AsciiDoc (README.adoc)
- All library code uses Ruby `autoload` (no `require_relative` or internal `require`)
- Error hierarchy: `Lutaml::Store::Error` → `ConfigurationError`, `BackendError`, `ModelNotRegisteredError`, `InvalidKeyError`, `PolymorphicUpdateError`, `CompositeModelError`
