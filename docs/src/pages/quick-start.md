---
layout: ../layouts/Docs.astro
---

# Quick Start

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lutaml-store'
```

And then execute:

```sh
$ bundle install
```

Or install it yourself as:

```sh
$ gem install lutaml-store
```

For SQLite backend support, also add:

```ruby
gem 'sqlite3'
```

## Define your models

```ruby
require 'lutaml/model'
require 'lutaml/store'

class Studio < Lutaml::Model::Serializable
  attribute :studio_key, :string
  attribute :name, :string
  attribute :location, :string
end

class PotteryClass < Lutaml::Model::Serializable
  attribute :studio, Studio
  attribute :class_id, :string
  attribute :description, :string
end

class Enrollment < Lutaml::Model::Serializable
  attribute :pottery_class, PotteryClass
  attribute :student_name, :string
end
```

## DatabaseStore: CRUD with model registry

```ruby
store = Lutaml::Store.new(
  adapter: { type: :filesystem, location: "./data" },
  models: [
    { model: Studio, key: :studio_key },
    { model: PotteryClass, key: :class_id },
    { model: Enrollment, key: :student_name }
  ]
)

# Save a model
store.save(Studio.new(studio_key: "st-001", name: "Riverside Pottery", location: "123 River St"))

# Fetch by key
studio = store.fetch(model: Studio, studio_key: "st-001")

# Update with dot-notation
store.update(model: Studio, studio_key: "st-001") do |s|
  s.name = "Riverside Pottery Studio"
end

# Delete
store.destroy(model: Studio, studio_key: "st-001")
```

## CacheStore: TTL-aware caching

```ruby
cache = Lutaml::Store::CacheStore.new(
  adapter: { type: :memory },
  default_ttl: 3600,     # 1 hour
  max_size: 1000         # LRU eviction
)

cache.set("key", "value", ttl: 1800)
cache.get("key")          # "value" (within TTL)
cache.exists?("key")      # true
cache.fetch("key") { expensive_computation }  # block on miss
```

## PackageStore: multi-model packages

```ruby
package = Lutaml::Store::PackageStore.new(definition)
package.add_model(Studio.new(studio_key: "st-001", name: "Riverside"))
package.save("./my-package", transport: :directory)

# Load it back
loaded = Lutaml::Store::PackageStore.load(definition, "./my-package")
loaded.fetch_model(Studio, "st-001")
```
