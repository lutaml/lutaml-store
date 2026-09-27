---
layout: ../layouts/Docs.astro
---

# Sources

A **Source** is a read-only view over a LutaML data repository. It answers four questions:

- Does a key exist? (`exist?`)
- What are its bytes? (`read`)
- Which keys exist? (`keys`, `each_key`)
- What does the repository's manifest declare? (`manifest`)

Sources **never write**. Selection is explicit — `Source.for(type, options)` raises `ConfigurationError` for a missing option; there is no discovery, no fallback, and no magic.

## Available sources

| Type | What | Key options |
|---|---|---|
| `:directory` | A local package directory (`manifest.json` + `entries/`) | `path:` |
| `:zip` | A `.zip` package read in place | `path:` |
| `:https` | Any static HTTP host (Pages, raw, buckets) | `base_url:` |
| `:rest` | The lutaml cloud store API | `base_url:`, `collection:` |

## Error contract

A definitive miss raises `NotFoundError`; transport trouble raises `BackendError`. Consumers can distinguish "absent" from "network broke":

```ruby
begin
  source.read("RFC 9999")
rescue Lutaml::Store::NotFoundError
  # definitively not in the repository
rescue Lutaml::Store::BackendError
  # network/service failure — retryable
end
```

## Usage

```ruby
# Directory source
src = Lutaml::Store::Source.for(:directory, path: "~/gcr/relaton/ietf")

# Zip source
src = Lutaml::Store::Source.for(:zip, path: "ietf-distribution.zip")

# HTTPS source (any static host)
src = Lutaml::Store::Source.for(:https,
  base_url: "https://raw.githubusercontent.com/relaton/relaton-data-ietf/main/data/")

# REST source (the lutaml cloud store contract)
src = Lutaml::Store::Source.for(:rest,
  base_url: "https://api.relaton.org", collection: "ietf")

# Common operations
src.keys                      # => ["RFC 7231", "RFC 3986", ...]
src.read("RFC 7231")          # => bytes
src.exist?("RFC 7231")        # => true
src.get("RFC 7231", MyModel)  # => typed model (model class declared)
src.search(docid: "RFC 7231") # => matching manifest entries
```

## The Https transport

The `:https` source supports:
- **ETag/304 revalidation** via an optional `cache:` config (`HttpCacheConfig` hash)
- **Injected transport** (`transport:` callable) for tests and alternate HTTP stacks
- **Redirect budget** (`max_redirects:` default 3)
- **Auth headers** (`headers:`) for private repositories

## The Rest contract

The `:rest` source implements the lutaml cloud store API contract:

```
GET {base}/collections                      → collection list
GET {base}/collections/{c}/manifest         → Manifest
GET {base}/collections/{c}/entries/{key}    → record
GET {base}/collections/{c}/shards/{n}       → shard keys (optional)
```

404 is a definitive "no such key/collection"; every other non-2xx is a `BackendError`.
