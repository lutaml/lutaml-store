# TODO.impl/1-lutaml-hal-migration.md

# Migration Plan: lutaml-hal → lutaml-store

## Completed

### Anti-pattern elimination (all done)

All `instance_variable_set/get`, `send(:private_method)`, and `respond_to?` calls
have been eliminated from `lib/lutaml/hal/`.

| File | Changes |
|---|---|
| `resource.rb` | Added `embedded_data=` setter; `from_embedded` uses `public_send` instead of `instance_variable_set` |
| `page.rb` | `instance_variable_get` → `public_send(Hal::REGISTER_ID_ATTR_NAME)` |
| `model_register.rb` | All methods used by Link made public; `instance_variable_set` → `embedded_data=`; `instance_variable_set` for register ID → `public_send(setter)`; `send(key)` → `public_send(key)`; `respond_to?(:status)` → `faraday_response?(response) && response.status == 304` |
| `link.rb` | Removed all `register.send(:private_method, ...)` calls (4 instances); `instance_variable_get` → `public_send`; `respond_to?(:embedded_data)` → `is_a?(Resource)` type check |
| `global_register.rb` | Removed `respond_to?` checks from `clear_all_caches` and `cache_stats` |
| `cache/cache_metadata.rb` | Extracted `ResponseHeaders` and `ResponseStatus` modules replacing `respond_to?` proc lambdas |
| `cache/cache_manager.rb` | `respond_to?` → `rescue NoMethodError` for optional methods; `is_a?` type check for HttpCache; proper HttpCache API delegation (`get(:get, url)`, `set(:get, url, {}, response)`) |
| `rate_limiter.rb` | Simplified with `is_a?` type check |

### Cache architecture fixes

- `http_aware?` now requires explicit opt-in (`http_aware == true`) instead of defaulting to true when HttpCache is available
- `CacheManager` properly delegates to `HttpCache`'s method/url API (`get(:get, url)`, `set(:get, url, {}, response)`, `delete(:get, url)`)
- Non-http-aware path uses `SimpleCacheStore` (in-memory, no serialization) instead of `CacheStore` (which JSON-serializes and can't handle `CacheEntry` objects)
- Removed `create_basic_cache` method (no longer needed)

### Spec fixes

- `cache_integration_spec.rb`: Fixed `REGISTER_ID_ATTR_NAME` (requires `lutaml/hal` instead of redefining constant); added `status: 200` to mock responses; fixed cache key in legacy test; removed `instance_variable_get`/`send` usage
- `cache_manager_spec.rb`: Updated stats tests to stub `stats` (not `cache_info`); updated `http_aware_cache?` test to use `is_a?` instead of `respond_to?`; fixed `get_from_http_cache` test signature
- `cache_configuration_spec.rb`: Fixed `http_aware?` nil default expectation; fixed adapter_config error type
- `cache_metadata_spec.rb`: Added `status: 200` to test doubles

### Test results

- **lutaml-hal**: 210 examples, 0 failures
- **lutaml-store**: 248 examples, 1 pre-existing failure (vary header spec) + 25 pre-existing failures in HTTP cache integration specs
- **Anti-patterns in lib code**: 0 `instance_variable_set/get`, 0 `send`, 0 `respond_to?`

## Implemented in lutaml-hal#15

The realized-object cache (relaton/w3c_api#11) is working and opt-in
(`ModelRegister.new(..., cache: {...})`; no config keeps the previous
behavior). Delivered across four commits on `rt-add-lutaml-store`:

### Phase 1: Make caching work / unify through lutaml-store — done (adapted)

- The cache path was crashing; fixed: require `lutaml/store` (so its autoloads
  resolve), route `Link#realize` through the public `cache_manager` API, add
  `Client#get_by_url_with_headers`, remove `Client`'s legacy `@cache` Hash,
  make HTTP-aware caching explicit opt-in.
- **Deviation:** instead of a `HalStore` wrapper, `CacheManager` uses
  lutaml-store's `CacheStore` directly for persistent adapters and keeps
  `SimpleCacheStore` for the in-memory adapter (so cache hits avoid
  serialization). `SimpleCacheStore` was therefore retained, not removed.

### Phase 2: Register ID / embedded data as proper attributes — done

- Dropped the `Hal::REGISTER_ID_ATTR_NAME` constant and all dynamic
  `instance_variable_get/set("@#{...}")`; `Resource`/`Link`/`LinkSet` use
  `attr_accessor :_global_register_id`, embedded data is an `attr_accessor`.
- Also removed the remaining `register.send(:private_method)` calls from
  `Link` by making `ModelRegister#find_matching_model_class` public.

### Phase 3: Persistence + URL keying — done (alternative to model-registry)

- **URL keying:** `CacheManager` canonicalizes relative URLs to absolute before
  keying, so a resource fetched by endpoint path and the same resource realized
  from an absolute link href share one entry (the core repeated-realize fix).
- **Persistence — decision:** rather than registering HAL resource classes in
  lutaml-store's model registry, `CacheEntry` gained a JSON storage form
  (records the model class + lutaml-model JSON). With a `filesystem`/`sqlite`
  adapter the cache persists via `Lutaml::Store::CacheStore` and rebuilds models
  on retrieval. This keeps the cache shape (`URL => entry`) and was chosen over
  the model-registry approach, whose `fetch(model:, key:)` API fits poorly with
  a heterogeneous URL→object lookup. Note: persisted entries require **named**
  resource classes with explicit `key_value` mappings.

## Still remaining

### HTTP-aware response cache (deferred)

Backing the HTTP-aware mode with lutaml-store's `HttpCache` (ETag / 304
revalidation against a cached response) is left as scaffolding
(`create_http_cache` / `*_http_cache` in `CacheManager`). It needs a realized
model to be reconstructed from a cached response (i.e. knowing the resource
class at read time) and is not required for the realized-object caching in #11.

### Release coordination

lutaml-hal#15 depends on lutaml-store via a `path:` Gemfile entry. lutaml-store
needs a tagged release before lutaml-hal can depend on a published version and
the PR can ship.
