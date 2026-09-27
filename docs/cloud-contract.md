# Cloud Store Contract

The lutaml cloud store API contract — distilled from api.relaton.org and generalized. Any service implementing it is a lutaml cloud store.

## The contract

```
GET {base}/collections                       → { collections: [...] }
GET {base}/collections/{c}/manifest          → Manifest (JSON)
GET {base}/collections/{c}/entries/{key}     → record bytes (ETag; 404 = not-found)
GET {base}/collections/{c}/shards/{n}        → { keys: [...] }   (optional)
```

## Rules

1. **Keys are URL-safe storage keys** — a single path segment with no raw `/`. Domain identifiers that contain slashes (docids like `ISO/IEC DIR 1`) travel in `entries[].metadata.docid`, and clients resolve reference → storage key through the manifest.

2. **404 is an answer, not an error** — clients raise `NotFoundError` (Ruby) or return `{ ok: false, reason: "not_found" }` (TS). Only 5xx / transport failures are retryable.

3. **Manifests are immutable per generation** — `version`, `generated`, `count` move together; shards are derived from the same generation.

4. **Sharding semantics are domain-owned** — the store/source only fetches named parts; the domain computes which shard (relaton: crc32 of pubid root number).

## The Manifest schema

```json
{
  "version": 1,
  "generated": "2026-09-27T00:00:00Z",
  "count": 178681,
  "shards": 256,
  "entries": [
    { "key": "rfc 7231", "digest": "sha256:...", "shard": 12, "metadata": { "docid": "RFC 7231" } }
  ]
}
```

## Reference implementation

api.relaton.org serves 30 collections (flavors) with 178k+ records:

- **Browsers** get server-rendered HTML: collections index, searchable record table, framed record pages
- **API clients** get JSON manifests and raw records from the same URLs
- **Content negotiation** on the `Accept` header — no separate site
