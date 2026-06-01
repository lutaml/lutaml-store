# TODO.impl/3-lutaml-jsonschema-migration.md

# Migration Plan: lutaml-jsonschema → lutaml-store

## Current state analysis

### How lutaml-jsonschema stores LutaML model objects

lutaml-jsonschema is a JSON Schema parser/generator/SPA builder. It has the
simplest storage profile of the three repos — it does **no persistent storage
at all**. Its "storage" is purely in-memory:

1. **`SchemaSet`** — holds `@schemas` (Hash of name → `Schema`), `@file_paths`
   (Hash), `@source_jsons` (Hash). Loaded from JSON files on disk.

2. **`ReferenceResolver`** — navigates `Schema` object graphs to resolve `$ref`
   pointers. No storage, pure computation.

3. **`Configuration`** — loads from YAML file. Simple config object, not a
   storage concern.

4. **`Combiner`** — merges multiple schemas. Pure computation.

5. **SPA generation** — `Spa::SpaBuilder`, `Spa::Generator` produce HTML/Vue
   output. Write-only, no storage.

### Architecture (current)

```
Lutaml::Jsonschema
├── SchemaSet (in-memory schema collection)
│     ├── @schemas (Hash name → Schema)
│     ├── load_from_files → File.read → Schema.from_json
│     ├── load_from_directory → Dir.glob → load_from_files
│     ├── resolve_ref → ReferenceResolver
│     └── validate! → walks schema tree collecting errors
│
├── Schema (Lutaml::Model::Serializable)
│     └── Recursive JSON Schema model with composition, conditionals, etc.
│
├── PropertyEntry (Lutaml::Model::Serializable)
│     └── name + Schema pair
│
├── Link (Lutaml::Model::Serializable)
│     └── JSON Hyper-Schema link
│
├── ReferenceResolver — navigates Schema graphs
├── Combiner — merges schemas
├── Configuration — YAML config loading
└── SPA generator — static site generation
```

### Key observation

lutaml-jsonschema is **not a storage application**. It's a **parsing and
transformation pipeline**. The storage it does (loading JSON files into memory)
is trivial — `File.read` → `Schema.from_json`.

However, there are storage-adjacent concerns where lutaml-store could help:

1. **Schema caching** — If the same schemas are loaded repeatedly (e.g., in a
   dev server), caching parsed `Schema` objects avoids re-parsing.

2. **Reference resolution caching** — `$ref` resolution is recursive and could
   benefit from memoization via a store.

3. **SPA incremental builds** — The SPA generator could use lutaml-store to
   cache intermediate build artifacts.

### Problems identified

| Category | Issue | Location |
|---|---|---|
| **No caching** | `SchemaSet.load_from_files` re-parses every time | `schema_set.rb:14-21` |
| **In-memory state** | `@source_jsons` and `@file_paths` are informal caches stored alongside `@schemas` | `schema_set.rb:36-38` |
| **No lazy loading** | All schemas loaded eagerly; no on-demand loading | `schema_set.rb` |
| **Duplicated index logic** | `ReferenceResolver`, `SchemaSet#find_schema_by_filename`, and `SchemaSet#resolve_file_ref` all do similar lookup work | Multiple |

## Migration strategy

### Phase 1: Use lutaml-store as a schema cache

The primary value of lutaml-store for this repo is **caching parsed schemas**
to avoid re-reading and re-parsing JSON files.

```ruby
module Lutaml
  module Jsonschema
    class SchemaStore
      def initialize(cache_config: {})
        @store = Lutaml::Store.new(
          adapter: cache_config[:adapter] || :memory,
          models: [
            { model: Schema, key: :dollar_id }
          ],
          cache: {
            enabled: true,
            ttl: cache_config[:ttl] || 3600,
            max_size: cache_config[:max_size] || 100
          }
        )
      end

      def load_schema(path, name: nil)
        name ||= File.basename(path, ".*")
        cached = @store.fetch(model: Schema, dollar_id: name)
        return cached if cached

        data = File.read(path)
        schema = Schema.from_json(data)
        @store.save(schema)
        schema
      end

      def fetch(name)
        @store.fetch(model: Schema, dollar_id: name)
      end

      def preload_directory(dir)
        Dir.glob(File.join(dir, "*.json")).each do |path|
          load_schema(path)
        end
      end
    end
  end
end
```

### Phase 2: Integrate `SchemaStore` into `SchemaSet`

`SchemaSet` currently loads all schemas eagerly. With `SchemaStore`:

```ruby
class SchemaSet
  def initialize(base_dir: nil, schema_store: nil)
    @schemas = {}
    @base_dir = base_dir
    @store = schema_store || SchemaStore.new
    @resolver = ReferenceResolver.new(@schemas)
  end

  def self.load_from_files(*paths, base_dir: nil)
    set = new(base_dir: base_dir)
    paths.each do |path|
      name = File.basename(path, ".*")
      schema = set.instance_variable_get(:@store).load_schema(path, name: name)
      set.add(name, schema, path)
    end
    set
  end
end
```

Schemas loaded through `SchemaStore` are automatically cached. Subsequent loads
hit the cache instead of re-parsing JSON.

### Phase 3: Cache reference resolution results

`ReferenceResolver` does recursive graph navigation. Add memoization via
lutaml-store:

```ruby
class ReferenceResolver
  def initialize(schemas = {}, resolution_cache: nil)
    @schemas = schemas
    @cache = resolution_cache  # Lutaml::Store instance or nil
  end

  def resolve(ref, root_schema = nil)
    cache_key = "#{root_schema&.dollar_id}:#{ref}"
    cached = @cache&.get(cache_key)
    return cached if cached

    result = perform_resolve(ref, root_schema)
    @cache&.set(cache_key, result)
    result
  end
end
```

### Phase 4: SPA incremental build cache

The SPA generator can use lutaml-store to cache generated artifacts:

```ruby
class Spa::Generator
  def initialize(schema_set, output_dir, cache_adapter: :filesystem)
    @schema_set = schema_set
    @output_dir = output_dir
    @artifact_cache = Lutaml::Store.new(
      adapter: { type: cache_adapter, path: File.join(output_dir, ".cache") }
    )
  end
end
```

This enables incremental SPA builds — only regenerate schemas that changed.

### Phase 5: Remove `@source_jsons` and `@file_paths`

These informal caches in `SchemaSet` become unnecessary once `SchemaStore`
handles caching. The raw JSON can be re-fetched from the store if needed, or
the schema's `to_json` can regenerate it.

## Completed

### Phase 1: SchemaStore with schema caching (done)

Created `Lutaml::Jsonschema::SchemaStore` backed by `Lutaml::Store` for schema
caching. Schemas loaded from JSON files are automatically cached — subsequent
loads hit the store instead of re-parsing.

Also fixed a composite model handler edge case: nested registered model
instances with nil keys are now skipped (they're part of the parent model,
not independently stored).

| File | Change |
|---|---|
| `lutaml-store/lib/lutaml/store/model_registry.rb` | `find_composite_models` skips nested models with nil keys |
| `lutaml-jsonschema/lib/lutaml/jsonschema/schema_store.rb` | Schema caching via `Lutaml::Store` |
| `lutaml-jsonschema/lib/lutaml/jsonschema.rb` | Require for schema_store |
| `lutaml-jsonschema/lutaml-jsonschema.gemspec` | Added `lutaml-store ~> 0.1.0` dependency |
| `lutaml-jsonschema/Gemfile` | Added lutaml-store path gem |
| `lutaml-jsonschema/spec/lutaml/jsonschema/schema_store_spec.rb` | 6 specs for SchemaStore CRUD + caching |
| `lutaml-jsonschema/spec/spec_helper.rb` | Added `fixture_path` helper |

### Test results

- **lutaml-store:** 19 core specs pass
- **lutaml-jsonschema:** 167 examples, 0 failures (no regressions)
- **lutaml-hal:** 210 examples, 0 failures
- **glossarist:** 1154 examples, 0 failures

## Remaining (future work)

| File | Purpose |
|---|---|
| `lib/lutaml/jsonschema/schema_store.rb` | Schema caching via `Lutaml::Store` |

## Files to modify

| File | Change |
|---|---|
| `schema_set.rb` | Accept optional `SchemaStore`; delegate loading to it; remove `@source_jsons`/`@file_paths` |
| `reference_resolver.rb` | Accept optional resolution cache |
| `spa/generator.rb` | Use `Lutaml::Store` for artifact caching |

## Spec coverage needed

1. **SchemaStore** — load, fetch, cache hit, cache miss, preload_directory
2. **SchemaSet with SchemaStore** — schemas loaded from cache on second call
3. **Reference resolution caching** — resolved refs cached, cache invalidated on schema change
4. **SPA incremental builds** — only changed schemas regenerated

## Risk assessment

- **Low risk overall** — this repo has the simplest integration. No persistent
  storage is being replaced, only caching is being added.
- **No backward compatibility risk** — `SchemaStore` is additive; existing
  `SchemaSet` API remains the same.
- **Cleanest migration path** — other repos can reference this as the simplest
  example of lutaml-store integration.

## Priority

This is the **lowest priority** migration because:
1. No broken encapsulation to fix (no `send`, `instance_variable_get/set`, `respond_to?`)
2. No storage layer to replace — only caching to add
3. The repo is clean and well-structured already

Recommended order: Fix lutaml-store self-quality first, then migrate
lutaml-hal (most urgent encapsulation issues), then glossarist (most complex),
then lutaml-jsonschema (polish/caching).
