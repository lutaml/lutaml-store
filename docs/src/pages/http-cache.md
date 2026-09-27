---
layout: ../layouts/Docs.astro
title: HTTP Caching
---

# HTTP Caching

`Lutaml::Store::HttpCache` provides HTTP-aware caching for network-backed sources, used by the `:https` and `:rest` sources. It is model-driven: cache state serializes through `to_json`/`from_json` on LutaML Model classes, not hand-rolled hashes.

## What it supports

- **ETags** — stored and re-sent as `If-None-Match`
- **Conditional requests** — a `304 Not Modified` response resolves to the cached body with zero transfer
- **Cache-Control** — `max-age`, `no-cache`, `no-store` directives are honored
- **Vary** — responses varied by header are cached separately

## Enabling on the HTTPS source

```ruby
src = Lutaml::Store::Source.for(:https,
  base_url: "https://data.example.com/index/",
  cache: { path: "./cache/http" }   # HttpCacheConfig hash
)

src.read("some-key")   # first call: 200, cached
src.read("some-key")   # revalidates with ETag; 304 → cached bytes
```

## Revalidation semantics

1. **Fresh window** (`max-age` not elapsed): served from cache without a request.
2. **Stale**: the source sends `If-None-Match`; on `304` the cached body is reused and freshness is extended.
3. **`no-store` / missing validators**: the response is returned but not cached.

## Transport injection

The `:https` source accepts an injected `transport:` callable for specs and alternate HTTP stacks, so cache behavior is fully testable without the network:

```ruby
transport = ->(uri, headers) { fake_response }
src = Lutaml::Store::Source.for(:https,
  base_url: "https://example.com/", transport: transport, cache: { path: tmpdir })
```
