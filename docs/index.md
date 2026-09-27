# Lutaml::Store

Store-centric database-style API for [Lutaml::Model](https://github.com/lutaml/lutaml-model) objects, with model registry, polymorphic support, composite relationships, and multiple storage backends.

It also provides **read-only Sources** for working with data repositories that live outside your process — GitHub Pages, any static host, a REST API, a local package directory, or a `.zip` distribution — through one facade that never guesses which layer answered.

## What it does

| Layer | Role |
|---|---|
| **Repository** | The uniform facade: one read API over any source (cloud, local, zip), explicit cache, online/offline modes |
| **Source** | Read-only views: `Directory`, `Zip`, `Https` (ETag/304), `Rest` (the lutaml cloud store API) |
| **Manifest** | The enumeration SSOT: keys, sha256 digests, opaque shard metadata |
| **Mirror** | Pull any source into a GCR-style package; pack to a distributable `.zip` |
| **DatabaseStore** | High-level CRUD with model registry, polymorphism, composites |
| **CacheStore** | TTL-aware cache with LRU eviction |
| **HttpCache** | HTTP-aware caching with ETags, conditional requests, Cache-Control |
| **PackageStore** | Structured multi-model packages with ZIP and directory transports |

## Installation

```ruby
gem "lutaml-store"
```

For SQLite backend support, also add:

```ruby
gem "sqlite3"
```

## Quick start: read a LutaML data repository

The same read API whether the data lives in the cloud, a local package, or a downloaded `.zip`:

```ruby
require "lutaml/store"

# From a cloud API (api.relaton.org is the reference implementation)
repo = Lutaml::Store::Repository.new(
  source: Lutaml::Store::Source.for(:rest,
    base_url: "https://api.relaton.org", collection: "ietf"),
  cache: Lutaml::Store::Source.for(:directory, path: "~/.cache/relaton/ietf"),
)

# From a local GCR-style package — identical read API
repo = Lutaml::Store::Repository.new(
  source: Lutaml::Store::Source.for(:directory, path: "~/gcr/relaton/ietf"),
)

# From a downloaded .zip distribution — same API
repo = Lutaml::Store::Repository.new(
  source: Lutaml::Store::Source.for(:zip, path: "ietf.zip"),
)
```

## Read, search, pull

```ruby
repo.read("RFC 7231")           # bytes
repo.exist?("RFC 7231")         # true
repo.keys                       # all keys
repo.manifest                   # Lutaml::Store::Manifest

repo.get("RFC 7231", MyModel)   # typed model — declared, never inferred
repo.search(docid: "RFC 7231")  # metadata filter

repo.pull!(into: "~/gcr/relaton", collection: "ietf")  # GCR-style package
```

## Offline mode

```ruby
offline = Lutaml::Store::Repository.new(
  source: repo.source, cache: repo.cache, mode: :offline
)
offline.read("RFC 7231")  # served from the local package, no network
```
