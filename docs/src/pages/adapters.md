---
layout: ../layouts/Docs.astro
title: Adapters
---

# Adapters

An **Adapter** is the physical storage backend. All adapters inherit from `Adapter::Base` and register into the adapter registry, resolved via `Adapter.resolve(:type, options)`.

| Type | Backend | Key options |
|---|---|---|
| `:memory` | In-process hash | — |
| `:filesystem` | One file per key under a directory | `location:` |
| `:sqlite` | SQLite database | `location:` (requires the `sqlite3` gem) |

## Usage

```ruby
adapter = { type: :filesystem, location: "./data" }   # passed to Lutaml::Store.new
adapter = { type: :sqlite,     location: "./data.db" }
adapter = { type: :memory }                            # tests, scratch data
```

## Registering a custom adapter

```ruby
class RedisAdapter < Lutaml::Store::Adapter::Base
  def initialize(options) = @redis = Redis.new(url: options[:url])
  # ...get/set/delete/keys/all...
end

Lutaml::Store::Adapter.register(:redis, RedisAdapter)

store = Lutaml::Store.new(
  adapter: { type: :redis, url: "redis://localhost:6379/0" },
  models: [{ model: Studio, key: :studio_key }]
)
```

The registry pattern keeps the store open for extension: adapters, formats, and sources are all pluggable without modifying the gem (open/closed principle).

## Notes

- **FileSystem** writes one file per key using the format's extension and `glob_pattern` — the directory layout is human-inspectable.
- **SQLite** requires `gem "sqlite3"` in your Gemfile; the store raises a helpful error if it is missing.
- **Memory** is ideal for specs and ephemeral data; entries vanish with the process.
