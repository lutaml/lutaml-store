---
layout: default
title: Lutaml::Store
---

# Lutaml::Store

Store-centric database-style API for [Lutaml::Model](https://github.com/lutaml/lutaml-model) objects.

## Quick start: read a LutaML data repository

```ruby
require "lutaml/store"

# From a cloud API
repo = Lutaml::Store::Repository.new(
  source: Lutaml::Store::Source.for(:rest,
    base_url: "https://api.relaton.org", collection: "ietf"),
  cache: Lutaml::Store::Source.for(:directory, path: "~/.cache/relaton/ietf"),
)

# From a local GCR-style package — identical read API
repo = Lutaml::Store::Repository.new(
  source: Lutaml::Store::Source.for(:directory, path: "~/gcr/relaton/ietf"),
)

repo.read("RFC 7231")        # bytes
repo.search(docid: "RFC 7231")
repo.pull!(into: "~/gcr/relaton", collection: "ietf")
```

## Features

- **Repository** — one read API over any source (cloud, local, zip)
- **Source** — Directory, Zip, Https, Rest (read-only)
- **DatabaseStore** — CRUD with model registry, polymorphism, composites
- **PackageStore** — structured multi-model packages
- **CacheStore** — TTL-aware cache
- **HttpCache** — ETag/304 revalidation
- **Mirror** — pull any source into a package; pack to .zip

## Installation

```ruby
gem "lutaml-store"
```

For SQLite backend support, also add `gem "sqlite3"`.
