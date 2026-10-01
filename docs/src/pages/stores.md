---
layout: ../layouts/Docs.astro
title: Stores
---

# Stores

## DatabaseStore — typed CRUD

```ruby
store = Lutaml::Store.new(
  adapter: { type: :filesystem, location: "./data" },
  models: [
    { model: Studio, key: :studio_key },
    { model: PotteryClass, key: :class_id },
    { model: Enrollment, key: :student_name }
  ]
)

store.save(Studio.new(studio_key: "st-001", name: "Riverside Pottery"))
studio = store.fetch(model: Studio, studio_key: "st-001")

store.update(model: Studio, studio_key: "st-001") do |s|
  s.name = "Riverside Pottery Studio"
end

store.destroy(model: Studio, studio_key: "st-001")
```

### Polymorphic models

Registering multiple models against the same key attribute enables polymorphic storage: fetching returns whichever registered model was stored under the key. Configure per-registration:

```ruby
models: [
  { model: Person, key: :email },
  { model: Organization, key: :email, polymorphic: true }
]
```

### Composite models

Nested registered models are stored independently; `CompositeModelHandler` restores object references on fetch. A `PotteryClass` that embeds a `Studio` keeps the studio in its own key space — updating the studio once updates every referencing object's view of it.

## BasicStore — key-value layer

```ruby
basic = Lutaml::Store::BasicStore.new(
  adapter: { type: :memory },
  cache: { type: :memory, ttl: 60 },
  monitor: my_monitor,          # optional
  events: [my_subscriber]       # optional
)

basic.set("key", "value")
basic.get("key")        # => "value"
basic.exists?("key")    # => true
basic.keys              # => ["key"]
basic.all               # => { "key" => "value" }
basic.delete("key")
```

## CacheStore — TTL and LRU

```ruby
cache = Lutaml::Store::CacheStore.new(
  adapter: { type: :memory },
  default_ttl: 3600,
  max_size: 1000
)

cache.set("key", "value", ttl: 1800)
cache.get("key")                          # "value" within TTL, nil after
cache.fetch("key") { expensive_call }     # block runs only on miss
```

Entries past their TTL are evicted lazily on access; when `max_size` is exceeded the least-recently-used entries are evicted first.

### TTL guarantees (pinned)

The TTL semantics are pinned by specs and safe to build expiry policy on:

- **Persistence** — entries serialize `created_at` as ISO-8601 with
  microsecond precision, so a FileSystem (or SQLite) cache reopened in a new
  process keeps every entry's original clock; expiry survives restarts.
  The memory adapter keeps no state across processes by nature.
- **Clock** — wall clock, not monotonic. This is the deliberate trade:
  wall-clock timestamps survive restarts, but a system clock jump changes
  apparent freshness (a backward jump un-expires nothing an entry's absolute
  `created_at + ttl` already expired). Consumers needing jump-immunity
  re-derive freshness from the source.
- **Expired reads** — `get` on an expired entry returns `nil` **and deletes
  the entry**: the key disappears from `keys`/`size`/`exists?`.
- **Sweep** — expiry is lazy-on-read plus an opportunistic
  `cleanup_expired` (interval `cleanup_interval`, default 300 s) invoked
  inside mutating reads. There is **no background reaper**; a consumer like
  the relaton shard cache needs none.
- **TTL values** — `ttl: nil` (and no `default_ttl`) never expires;
  `ttl: 0` is immediately expired.

## PackageStore — multi-model packages

```ruby
definition = Lutaml::Store::PackageDefinition.new do |d|
  d.model Studio
  d.model PotteryClass
  d.metadata version: "1.0"
end

package = Lutaml::Store::PackageStore.new(definition)
package.add_model(Studio.new(studio_key: "st-001", name: "Riverside"))
package.save("./my-package", transport: :directory)
package.save("./my-package.zip", transport: :zip)

loaded = Lutaml::Store::PackageStore.load(definition, "./my-package")
loaded.fetch_model(Studio, "st-001")
```

`PackageDefinition` declares which models, assets, and metadata a package contains; `DirectoryTransport` and `ZipTransport` handle reading and writing. Formats are chosen per model entry (see [Formats](/lutaml-store/formats/)).

## FormatSerializer — store in any format

`FormatSerializer` wraps a Format handler to implement the serialize/deserialize interface, letting `DatabaseStore` persist entries as YAMLS, XML, Marshal, etc. instead of the default hash serialization:

```ruby
store = Lutaml::Store.new(
  adapter: { type: :filesystem, location: "./data" },
  models: [{ model: GlossaryTerm, key: :id, format: :yamls }]
)
```

This is the pattern used for Glossarist-style multi-document YAML files.
