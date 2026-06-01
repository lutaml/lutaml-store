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

## Remaining (future work)

### Phase 1: Unify caching through lutaml-store

Create `HalStore` as a thin wrapper around `Lutaml::Store` for HAL-specific
caching. Remove `SimpleCacheStore` (replaced by lutaml-store memory adapter).
Remove `Client`'s `@cache` Hash. Simplify `CacheManager`.

### Phase 2: Register ID tracking as proper attribute

Replace `_global_register_id` instance variable with a proper
`Lutaml::Model::Serializable` attribute on `Resource`. Make embedded data a
proper attribute. Eliminates `Hal::REGISTER_ID_ATTR_NAME` constant.

### Phase 3: Store HAL resources as registered models

Register HAL resource classes with lutaml-store's model registry for direct
CRUD operations instead of wrapping them in `CacheEntry`.
