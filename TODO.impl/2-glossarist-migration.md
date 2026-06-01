# TODO.impl/2-glossarist-migration.md

# Migration Plan: glossarist-ruby → lutaml-store

## Current state analysis

### How glossarist stores LutaML model objects

Glossarist is the most complex of the three repos. It manages glossary/terminology
concepts with multiple versions (v1, v2, v3) and several storage mechanisms:

1. **Filesystem YAML persistence** — `ConceptManager` reads/writes concept YAML
   files from a directory structure. Concepts are stored as:
   - `concept/{uuid}.yaml` — the managed concept
   - `localized_concept/{uuid}.yaml` — per-language localizations
   - Grouped files: `{uuid}.yaml` containing concept + all localizations

2. **ZIP package (GCR format)** — `GcrPackage` reads/writes concepts from ZIP
   archives containing `metadata.yaml`, `concepts/*.yaml`, optional compiled
   formats (TBX, JSON-LD, Turtle), and dataset assets.

3. **In-memory collections** — `ManagedConceptCollection`, `Collection`,
   `Collections::Collection`, `Collections::TypedCollection` — all use plain
   Arrays/Hashes to hold models in memory.

### Architecture (current)

```
Glossarist module
├── Collection (v1)
│     ├── @index (Hash id → Concept)
│     ├── @path (String — filesystem path)
│     ├── load_concepts → Dir.glob → Concept.from_yaml
│     └── save_concepts → File.write(Psych.dump)
│
├── ManagedConceptCollection (v2/v3)
│     ├── @managed_concepts (Array)
│     ├── @managed_concepts_ids (Hash id → uuid)
│     ├── load_from_files → ConceptManager
│     └── save_to_files → ConceptManager
│
├── ConceptManager
│     ├── path, localized_concepts_path
│     ├── load_from_files → Dir.glob → ConceptDocument.from_yamls → ManagedConcept
│     ├── save_to_files → File.write(to_yaml)
│     ├── save_grouped_concepts_to_files
│     └── Versioned concept document classes (v2, v3)
│
├── GcrPackage
│     ├── write → Zip::File → concept YAMLs + metadata
│     ├── read → Zip::File → parse → ManagedConcept instances
│     └── Compiled format generation (TBX, JSON-LD, Turtle)
│
├── ConceptCollector
│     └── Static methods for scanning directories, detecting schema versions
│
└── Model classes (all Lutaml::Model::Serializable):
      ├── ManagedConcept (key: identifier/uuid)
      ├── LocalizedConcept (inherits Concept)
      ├── ConceptData
      ├── Designation::Base (polymorphic)
      ├── DetailedDefinition
      ├── ConceptSource
      └── ... many more
```

### Key observations

**Glossarist has no storage abstraction.** File I/O is scattered across:
- `Collection#load_concepts`, `Collection#save_concept_to_file`
- `ConceptManager#load_concept_from_file`, `ConceptManager#save_concept_to_file`
- `GcrPackage#write`, `GcrPackage#read`
- `ConceptCollector` (static methods doing Dir.glob)

**Every storage operation is ad-hoc:**
- YAML serialization uses `Lutaml::Model::Serializable#to_yaml` / `.from_yaml`
- File naming uses concept UUIDs
- Directory layout is version-dependent
- ZIP packaging duplicates the filesystem logic

### Problems identified

| Category | Issue | Location |
|---|---|---|
| **No storage abstraction** | File I/O is in `ConceptManager`, `Collection`, `GcrPackage`, `ConceptCollector` — no single persistence layer | Multiple |
| **MECE violation** | `ManagedConceptCollection` manages an Array + a separate id→uuid Hash — this is a database, but hand-rolled | `managed_concept_collection.rb` |
| **DRY violation** | YAML file I/O patterns repeated in `Collection`, `ConceptManager`, `GcrPackage` | Multiple |
| **Schema version branching** | Version detection (v1/v2/v3) is sprinkled through `ConceptCollector`, `ConceptManager`, `SchemaMigration` | Multiple |
| **Lazy loading missing** | `Collection` has a TODO: "Add support for lazy concept loading" — all concepts loaded eagerly into memory | `collection.rb:4` |
| **OCP violation** | Adding a new storage backend (e.g., database) requires modifying `ConceptManager`, `Collection`, and `GcrPackage` | Multiple |

## Migration strategy

### Phase 1: Define a `ConceptStore` interface backed by lutaml-store

The core insight: Glossarist's concept management is a CRUD store with:
- **Model:** `ManagedConcept` (key: `uuid`)
- **Composite models:** `LocalizedConcept` instances per language
- **Backends:** Filesystem YAML, ZIP archive, and (future) SQLite

```ruby
module Glossarist
  class ConceptStore
    def initialize(adapter:, schema_version: "3")
      @store = Lutaml::Store.new(
        adapter: adapter,
        models: [
          {
            model: Glossarist::ManagedConcept,
            key: :uuid,
            polymorphic_class_key: nil
          },
          {
            model: Glossarist::LocalizedConcept,
            key: :uuid
          }
        ]
      )
      @schema_version = schema_version
    end

    # CRUD operations
    def save(managed_concept) = @store.save(managed_concept)
    def fetch(uuid) = @store.fetch(model: ManagedConcept, uuid: uuid)
    def fetch_by_id(id) = where(model: ManagedConcept, identifier: id).first
    def update(uuid, **attrs) = @store.update(model: ManagedConcept, uuid: uuid, attributes: attrs)
    def delete(uuid) = @store.destroy(model: ManagedConcept, uuid: uuid)

    # Query
    def all = @store.all(model: ManagedConcept)
    def where(model:, **conditions) = @store.where(model: model, **conditions)
    def count = @store.count(model: ManagedConcept)

    # Composite model access
    def fetch_localized(managed_concept_uuid, lang)
      concept = fetch(managed_concept_uuid)
      concept&.localization(lang)
    end
  end
end
```

### Phase 2: Implement filesystem adapter for Glossarist

Glossarist's filesystem layout is specific:

```
concepts/
  concept/
    {uuid}.yaml
  localized_concept/
    {uuid}.yaml
```

This maps to lutaml-store's FileSystem adapter with custom path resolution:

```ruby
store = Glossarist::ConceptStore.new(
  adapter: {
    type: :filesystem,
    path: "/path/to/concepts",
    extension: "yaml",
    # Custom naming: use uuid as filename, organize by model type
    naming_strategy: :uuid,
    directory_layout: {
      ManagedConcept => "concept",
      LocalizedConcept => "localized_concept"
    }
  }
)
```

This requires extending lutaml-store's FileSystem adapter to support:
- **Custom directory layout** (model type → subdirectory)
- **Custom key-to-filename mapping** (UUID-based naming)
- **YAML serialization** (already supported by lutaml-model)

Alternatively, add a `Glossarist::Adapters::YamlFilesystem` adapter that
implements `Lutaml::Store::Adapter::Base`.

### Phase 3: Implement ZIP archive adapter

GCR packages are ZIP archives. Create a `Glossarist::Adapters::ZipArchive`
adapter:

```ruby
class ZipArchive < Lutaml::Store::Adapter::Base
  def initialize(config)
    @zip_path = config[:path]
    # ...
  end

  def save(key, data, metadata = {})
    Zip::File.open(@zip_path, create: true) do |zf|
      zf.get_output_stream(key_to_entry_name(key)) do |f|
        f.write(data.to_yaml)
      end
    end
  end

  def load(key)
    Zip::File.open(@zip_path) do |zf|
      entry = zf.find_entry(key_to_entry_name(key))
      entry&.get_input_stream&.read
    end
  end
  # ... implement remaining Adapter::Base methods
end
```

This makes `GcrPackage` a thin wrapper around `ConceptStore` with a ZIP adapter.

### Phase 4: Migrate `ManagedConceptCollection`

Replace the hand-rolled Array + Hash index with `ConceptStore`:

```ruby
class ManagedConceptCollection
  def initialize(store:)
    @store = store  # Glossarist::ConceptStore
  end

  def fetch(uuid) = @store.fetch(uuid)
  def store(concept) = @store.save(concept)
  def each(&block) = @store.all.each(&block)

  # Remove: @managed_concepts array, @managed_concepts_ids hash
  # Remove: load_from_files, save_to_files (delegate to store)
end
```

### Phase 5: Migrate `Collection` (v1)

The v1 `Collection` follows the same pattern but simpler:

```ruby
class Collection
  def initialize(store:)
    @store = store
  end

  def fetch(id) = @store.fetch_by_id(id)
  def store(concept) = @store.save(concept)
  # Remove: @index, @path, load_concepts, save_concepts
end
```

### Phase 6: Migrate `GcrPackage`

`GcrPackage` becomes a factory that creates a `ConceptStore` with a ZIP adapter:

```ruby
class GcrPackage
  def self.load(zip_path)
    store = ConceptStore.new(adapter: { type: :zip, path: zip_path })
    metadata = load_metadata(zip_path)
    concepts = store.all
    new(zip_path, metadata, concepts)
  end

  def self.create(concepts:, metadata:, output_path:, **opts)
    store = ConceptStore.new(adapter: { type: :zip, path: output_path })
    store.save(concepts)
    write_metadata(output_path, metadata)
    # Compiled format generation stays here — it's a presentation concern
  end
end
```

### Phase 7: Migrate `ConceptCollector`

`ConceptCollector` currently has 230 lines of directory-scanning logic.
With lutaml-store, most of this becomes:

```ruby
def collect(dir)
  store = ConceptStore.new(adapter: { type: :filesystem, path: dir })
  store.all
end
```

Version detection logic moves into the adapter layer.

## Completed

### Phase 1: ConceptStore with custom serializer (done)

Created `Glossarist::ConceptStore` backed by `Lutaml::Store` with full CRUD.

**Problem:** `ManagedConcept` uses `key_value` DSL that maps both `uuid` and
`identifier` to the same `"id"` hash key — lossy for storage.

**Solution:** Added pluggable serializer support to lutaml-store:
- `ModelRegistration` now accepts `serializer:` option
- `ModelSerializer` delegates to custom serializer when registered
- Created `Glossarist::ConceptSerializer` — attribute-based serialization that
  uses attribute names as hash keys (bypasses `key_value` mappings entirely)

| File | Change |
|---|---|
| `lutaml-store/lib/lutaml/store/model_registration.rb` | Added `serializer` attr_reader and option |
| `lutaml-store/lib/lutaml/store/model_serializer.rb` | Accepts `registration` param, delegates to custom serializer |
| `lutaml-store/lib/lutaml/store/database_store.rb` | Passes registration to serialize/deserialize calls |
| `lutaml-store/spec/lutaml/store/custom_serializer_spec.rb` | 4 specs for custom serializer feature |
| `glossarist/lib/glossarist/concept_serializer.rb` | Attribute-based serializer for ManagedConcept |
| `glossarist/lib/glossarist/concept_store.rb` | CRUD store backed by lutaml-store with custom serializer |
| `glossarist/lib/glossarist.rb` | Autoloads for ConceptSerializer, ConceptStore |
| `glossarist/Gemfile` | Fixed lutaml-store path (`../../lutaml/lutaml-store`) |
| `glossarist/glossarist.gemspec` | Added `lutaml-store ~> 0.1.0` dependency |
| `glossarist/spec/unit/concept_serializer_spec.rb` | 4 specs for serializer round-trip |
| `glossarist/spec/unit/concept_store_spec.rb` | 12 specs for full CRUD |

### Test results

- **lutaml-store:** 19 core specs pass (database_store + custom_serializer)
- **glossarist:** 1154 examples, 0 failures (no regressions)

## Remaining (future work)

| File | Purpose |
|---|---|
| `lib/glossarist/concept_store.rb` | Glossarist-specific store backed by `Lutaml::Store` |
| `lib/glossarist/adapters/yaml_filesystem.rb` | Custom filesystem adapter for Glossarist's YAML layout |
| `lib/glossarist/adapters/zip_archive.rb` | ZIP archive adapter for GCR packages |

## Files to modify

| File | Change |
|---|---|
| `managed_concept_collection.rb` | Replace Array/Hash with `ConceptStore`; remove `load_from_files`/`save_to_files` |
| `collection.rb` | Replace `@index` with `ConceptStore`; remove `load_concepts`/`save_concepts` |
| `gcr_package.rb` | Use `ConceptStore` with ZIP adapter; keep compiled format generation |
| `concept_manager.rb` | Simplify to delegate to `ConceptStore`; remove raw File I/O |
| `concept_collector.rb` | Replace directory scanning with `ConceptStore.new(...).all` |
| `glossarist.rb` | Add autoloads for new classes |

## Spec coverage needed

1. **ConceptStore CRUD** — save, fetch, update, delete for ManagedConcept
2. **Composite model storage** — LocalizedConcept stored independently
3. **Filesystem adapter** — reads/writes Glossarist's directory layout
4. **ZIP adapter** — round-trip through GCR packages
5. **Schema version handling** — v1, v2, v3 concepts load correctly
6. **Lazy loading** — concepts loaded on demand, not all at once
7. **Migration backward compatibility** — existing YAML files still readable

## Risks

- **High complexity:** Glossarist has v1/v2/v3 schema migration paths. The
  storage layer must handle all versions transparently.
- **Medium risk:** ZIP adapter must handle streaming mode for large glossaries.
- **Low risk:** Replacing `ManagedConceptCollection`'s Array — straightforward
  delegation.

## Dependencies

- **lutaml-store must first** support custom filesystem layouts and YAML
  serialization natively. See `0-lutaml-store-self-quality.md`.
- **lutaml-store adapter interface** may need extension for ZIP archive support.
