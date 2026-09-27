---
layout: ../layouts/Docs.astro
title: Architecture
---

# Architecture

lutaml-store is a Ruby gem providing a **store-centric, database-style API** for persisting LutaML Model objects across multiple storage backends. It is deliberately split into two layers: a high-level typed store for application code, and a composable low-level toolkit (adapters, formats, sources) underneath.

## Two-layer store design

**`Lutaml::Store.new(adapter:, models:)`** — the primary entry point. Returns a `DatabaseStore` with:

- A **model registry** mapping model classes to their key attributes
- CRUD operations: `save`, `fetch`, `update`, `destroy`
- Polymorphic model handling (one key space, multiple models)
- Composite model relationships (nested registered models stored independently, references restored on fetch)
- Dot-notation nested updates (`store.update(model: Studio, studio_key: "st-001") { |s| s.name = "..." }`)

**`Lutaml::Store::BasicStore`** — the low-level key-value layer: `get`, `set`, `delete`, `exists?`, `all`, `keys`, plus bulk operations. It wraps a storage adapter with optional caching, monitoring, and event emission.

## Key classes

| Class | Role |
|---|---|
| `DatabaseStore` | High-level CRUD with model registry, composite models, polymorphism, file I/O |
| `BasicStore` | Low-level key-value store with optional cache/monitor/events |
| `CacheStore` | TTL-aware cache store extending `BasicStore` (LRU eviction) |
| `PackageStore` | Structured multi-model packages with directory/ZIP transport |
| `PackageDefinition` | Declarative schema for package structure (models, assets, metadata) |
| `ModelRegistry` / `ModelRegistration` | Register models with key fields and polymorphic config |
| `CompositeModelHandler` | Stores nested registered models independently, restores references |
| `AttributeUpdater` | Updates including dot-notation paths and block-based updates |
| `ModelSerializer` | Hash-based serialization/deserialization for key-value storage |
| `FormatSerializer` | Bridges any Format handler to the `ModelSerializer` interface |
| `Format` | Multi-format file I/O (YAML, YAMLS, JSON, JSONL, Marshal, XML) |
| `Adapter` | Storage adapter registry and factory (Memory, FileSystem, SQLite) |

## Source layer (read-only data repositories)

For consuming published data — rather than writing your own — the Source layer reads LutaML data repositories:

- **Sources** (`Source.for(type, options)`): `:directory`, `:zip`, `:https`, `:rest` — read-only views answering `exist?`, `read`, `keys`, `manifest`. See [Sources](/lutaml-store/sources/).
- **Manifest**: a `Lutaml::Model::Serializable` declaring entries (key, location, digest, shard, metadata), generation, and shard count.
- **Mirror**: `pull` a source into a local package incrementally with digest verification; `pack` a local package into a distributable `.zip`.
- **Repository**: the uniform consumer facade — `read`, `get`, `search`, `keys`, `manifest`, `pull!`, `exist?` — with a read-through cache so a mirrored local package and a cloud store are interchangeable.

## Design principles

1. **Open/closed.** New formats, adapters, and sources register themselves (`Format.register`, `Adapter.register`) without modifying existing code.
2. **Explicit selection, no magic.** `Source.for(type, options)` raises `ConfigurationError` for a missing option — no discovery, no fallback.
3. **Errors are distinguished.** `NotFoundError` means "definitively absent"; `BackendError` means "transport/backend trouble, retryable". Consumers never confuse the two.
4. **Byte-verbatim storage.** Reads and writes are binary-safe (`binread`/`binwrite`); records round-trip unchanged.
5. **Model-driven.** Everything above the adapter layer speaks LutaML Model instances, not hashes — serialization goes through declared attributes and mappings.

## Error hierarchy

```
Lutaml::Store::Error
├── ConfigurationError
├── BackendError
├── ModelNotRegisteredError
├── InvalidKeyError
├── PolymorphicUpdateError
└── CompositeModelError
```

`NotFoundError` (Source layer) inherits from `Error` as well, and is the definitive-miss signal distinct from `BackendError`.
