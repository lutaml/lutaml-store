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
| `DatabaseStore` | High-level CRUD with model registry, composite models, polymorphism |
| `BasicStore` | Low-level key-value store with optional cache/monitor/events |
| `CacheStore` | TTL-aware cache store extending `BasicStore` |
| `ModelRegistry` / `ModelRegistration` | Register models with their key fields and polymorphic config |
| `CompositeModelHandler` | Stores nested registered models independently, restores references |
| `AttributeUpdater` | Processes updates including dot-notation paths and block-based updates |
| `ModelSerializer` | Single point of serialization/deserialization for Lutaml::Model objects |
| `Config` | Parses and validates store configuration (adapter, cache, monitoring, compression) |

### Storage adapters (`lib/lutaml/store/adapter/`)

All inherit from `Adapter::Base`. Three backends: `Memory`, `FileSystem`, `SQLite`. The `DatabaseStore` creates the adapter internally via `BasicStore`; the adapter type is passed as `adapter: :memory`, `adapter: { type: :filesystem, path: "..." }`, etc.

### HTTP caching

`HttpCache` provides HTTP-aware caching with ETags, conditional requests (304), Cache-Control, and Vary header support. Used by lutaml-hal to avoid re-fetching HAL resources.

### Serialization & integrity

`Compression` adds gzip support. `Integrity` provides SHA256 checksums for data verification (used by the FileSystem adapter).

## Conventions

- Double-quoted strings (Rubocop enforced)
- Specs use `expect` syntax (no `should`)
- Documentation is in AsciiDoc (README.adoc, plan.adoc)
- Error hierarchy: `Lutaml::Store::Error` → `ConfigurationError`, `BackendError`, `ModelNotRegisteredError`, `InvalidKeyError`, `PolymorphicUpdateError`, `CompositeModelError`
