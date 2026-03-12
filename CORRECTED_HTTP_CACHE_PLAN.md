# Corrected HTTP Cache Implementation Plan

## Problem Statement

The previous implementation was fundamentally flawed. Instead of integrating HTTP caching transparently with the w3c_api gem, it bypassed the gem entirely by creating a SimpleHttpClient and making direct HTTP calls. This defeats the purpose of transparent caching integration.

## Correct Architecture Understanding

### Current Flow (w3c_api gem)
```
relaton-w3c → w3c_api.Client.specifications() → W3cApi::Hal.instance.register.fetch() → lutaml-hal HTTP client → W3C API
```

### Required Integration Point
The cache must be integrated at the `lutaml-hal` ModelRegister level, specifically in the `fetch()` method, so that when w3c_api calls `register.fetch()`, the cache transparently intercepts and handles HTTP requests.

### Correct Cache Flow
```
relaton-w3c → w3c_api.specifications() → W3cApi::Hal.register.fetch() → [HTTP CACHE HERE] → HTTP request (if cache miss)
```

### Monitoring cache

Add a CACHE debug mode to log cache hits/misses. Use the "Paint" gem to output cache activity in a visually distinct way and with appropriate emojis.

### Store inspection

Add a method outputting pretty content to inspect the cache store contents for debugging purposes.

## Key Files Analysis

### w3c_api Architecture
- **`w3c_api/lib/w3c_api/client.rb`**: Contains all public API methods like `specifications()`, `specification()`, etc.
- **`w3c_api/lib/w3c_api/hal.rb`**: Sets up lutaml-hal ModelRegister with W3C API endpoints
- **Integration Point**: All client methods call `fetch_resource()` which calls `Hal.instance.register.fetch()`

### lutaml-hal Integration
- **`lutaml-hal/lib/lutaml/hal/model_register.rb`**: Contains the `fetch()` method that makes HTTP requests
- **Cache Integration Point**: The `fetch()` method needs to check cache before making HTTP requests

## Implementation Plan

### Phase 1: lutaml-hal ModelRegister Cache Integration

**Modify `lutaml-hal/lib/lutaml/hal/model_register.rb`:**

1. **Add cache_store attribute:**
   ```ruby
   class ModelRegister
     attr_accessor :cache_store

     def initialize(name:, client:, cache_store: nil)
       @cache_store = cache_store
       # existing code...
     end
   end
   ```

2. **Modify fetch() method to use cache:**
   ```ruby
   def fetch(endpoint_id, **params)
     if @cache_store
       # Generate cache key from endpoint + params
       cache_key = generate_cache_key(endpoint_id, params)

       # Try cache first
       cached_response = @cache_store.get(cache_key)
       return cached_response if cached_response

       # Cache miss - make HTTP request
       response = make_http_request(endpoint_id, params)

       # Store in cache
       @cache_store.set(cache_key, response)

       response
     else
       # No cache - direct HTTP request
       make_http_request(endpoint_id, params)
     end
   end
   ```

### Phase 2: w3c_api Cache Configuration

**Add cache configuration to `w3c_api/lib/w3c_api/hal.rb`:**

```ruby
class Hal
  def configure_cache(cache_store)
    register.cache_store = cache_store
  end
end
```

### Phase 3: Integration Example

**Usage in relaton-w3c:**
```ruby
# Configure cache
cache_config = {
  adapter_type: :filesystem,
  adapter_options: { path: "./cache/w3c_api" },
  default_ttl: 3600,
  respect_http_headers: true
}

cache = Lutaml::Store::HttpCache.new(cache_config)
W3cApi::Hal.instance.configure_cache(cache)

# Now all w3c_api calls use cache transparently
client = W3cApi::Client.new
specs = client.specifications(page: 1, items: 100)  # Cached
spec = client.specification("html5")                # Cached
```

### Phase 4: Fix Demo Scripts

**Replace all SimpleHttpClient usage with real w3c_api calls:**

```ruby
# WRONG (current implementation):
client = SimpleHttpClient.new
response = client.get("https://api.w3.org/specifications")

# CORRECT (fixed implementation):
client = W3cApi::Client.new
specs = client.specifications(page: 1, items: 100)
```

## Success Criteria

1. ✅ **Zero API Changes**: relaton-w3c code remains unchanged
2. ✅ **Transparent Caching**: Cache works through existing w3c_api method calls
3. ✅ **Proper Architecture**: Cache integrated at lutaml-hal ModelRegister level
4. ✅ **Real Integration**: Uses actual w3c_api gem methods, not direct HTTP calls
5. ✅ **HTTP Semantics**: Maintains existing HTTP cache implementation (ETags, etc.)

## Files to Modify

### lutaml-hal Changes
- `lib/lutaml/hal/model_register.rb` - Add cache_store support to fetch() method

### w3c_api Changes
- `lib/w3c_api/hal.rb` - Add cache configuration method

### Demo Fixes
- Replace all `SimpleHttpClient` usage with `W3cApi::Client` methods
- Show transparent caching through real API calls

### Tests
- Update integration tests to use real w3c_api methods
- Test cache behavior through ModelRegister.fetch()

## Key Insight

The fundamental error was bypassing the w3c_api gem architecture. The cache must integrate **within** the existing call chain, not replace it. This ensures:

- Zero breaking changes for users
- Proper architectural layering
- Transparent operation
- Real-world validation with actual gem usage

This corrected approach maintains the existing HTTP cache implementation (models, headers, etc.) but integrates it at the correct architectural level.
