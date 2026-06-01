# TODO.impl/0-lutaml-store-self-quality.md

# lutaml-store Internal Quality Fixes (prerequisite for migrations)

## Completed

All anti-patterns eliminated from `lib/`:

| Anti-pattern | Remaining in lib/ |
|---|---|
| `instance_variable_get/set` | 0 (only a comment reference) |
| `respond_to?` | 0 (only a comment reference) |
| `send` on private methods | 0 |

### Changes made

1. **Created `ModelSerializer`** — unified serialization/deserialization into one class, eliminating `respond_to?` chains and duplicated code across `DatabaseStore`, `CompositeModelHandler`, `Serializer`.
2. **Added `Store#emit_event`** public method — eliminated `instance_variable_get(:@events)`.
3. **Fixed `AttributeUpdater`** — uses proper constructors instead of `instance_variable_set/get`.
4. **Fixed `CacheStore`** — uses proper factory methods.
5. **Removed `respond_to?` from adapters** — calls methods directly on `Adapter::Base` interface.
6. **Removed `CacheInspector`** — unused code.
7. **Added custom serializer support** — `ModelRegistration` accepts `serializer:` option for models with non-standard serialization (e.g., glossarist's `key_value` DSL).

## Anti-pattern audit (current state)

### 1. `instance_variable_get` / `instance_variable_set` — breaks encapsulation

| File | Line | Usage |
|---|---|---|
| `database_store.rb` | 375 | `@store.instance_variable_get(:@events)&.emit(event, data)` |
| `model_store.rb` | 230 | Same pattern — reaching into `@store`'s internals |
| `attribute_updater.rb` | 228 | `model.instance_variable_set(var, upgraded_model.instance_variable_get(var))` — polymorphic upgrade hack |
| `cache_store.rb` | 45 | `entry.instance_variable_set(:@created_at, ...)` — bypassing constructor |

**Fix:** Expose proper public APIs on the objects being accessed:
- `Store` should expose `emit_event(event, data)` as a public method.
- `AttributeUpdater#try_polymorphic_upgrade` must use proper constructors or
  `Lutaml::Model::Serializable`'s own API — never copy instance variables.
- `CacheStore` should use factory methods or proper attribute setters.

### 2. `respond_to?` — poor typing / duck-typing smell

**24 occurrences across the codebase.** The worst offenders:

| File | Pattern | Fix |
|---|---|---|
| `composite_model_handler.rb` L102-133 | `respond_to?(:to_hash)`, `respond_to?(:from_hash)` | All models are `Lutaml::Model::Serializable` — use `is_a?` checks against a serialization protocol, or better, use `to_hash` directly via the type system |
| `database_store.rb` L288-327 | Same serialization dispatch via `respond_to?` | Extract a `SerializationAdapter` that knows how to (de)serialize `Lutaml::Model::Serializable` |
| `attribute_updater.rb` L87-129 | `respond_to?(setter_method)` | Use the model's attribute metadata from `Lutaml::Model::Serializable.attributes` |
| `serializer.rb` | 14 occurrences | Full rewrite needed — see below |
| `http_cache.rb` L112-142 | `@adapter.respond_to?(:clear)` | All adapters inherit from `Adapter::Base` which defines `#clear` — just call it |

**Fix strategy:**
- Create a `Serializable` protocol module (`Lutaml::Store::Serializable`) that
  formalizes the serialization contract (`to_store_hash`, `from_store_hash`).
- Replace all `respond_to?` with type-based dispatch or method calls on known base classes.
- For attribute validation, use `model.class.attributes` (from Lutaml::Model).

### 3. Duplicated serialization logic

`DatabaseStore#serialize_model`, `DatabaseStore#deserialize_model`,
`CompositeModelHandler#serialize_model`, `CompositeModelHandler#deserialize_model`
all contain identical `respond_to?` chains for `(to_hash|to_h|to_s)` and
`(from_hash|from_h|new)`.

**Fix:** Extract a single `Lutaml::Store::ModelSerializer` class:

```ruby
class ModelSerializer
  def serialize(model)
    model.to_hash.merge("_class" => model.class.name)
  end

  def deserialize(data, expected_class)
    klass = Object.const_get(data["_class"])
    klass.from_hash(data.except("_class", "_composite_models"))
  end
end
```

Since all registered models are `Lutaml::Model::Serializable`, they all have
`to_hash` and `from_hash`. No need for duck-typing fallback chains.

### 4. Event emission through encapsulation violation

Both `DatabaseStore` and `ModelStore` emit events via:
```ruby
@store.instance_variable_get(:@events)&.emit(event, data)
```

**Fix:** Add `Store#emit_event(event, data)` as a public method. The `events`
object is an internal implementation detail and should not be leaked.

### 5. `CacheInspector` — untested, unused?

Check if `cache_inspector.rb` is actually used anywhere. If not, remove it.

### 6. Open/closed principle violations

- `AttributeUpdater#try_polymorphic_upgrade` uses `instance_variable_set` and
  `model.extend(registered_class)` — this is metaprogramming that breaks OCP.
  Instead, create a new model instance of the subclass and replace the reference.

## Implementation order

1. **Add `Store#emit_event` public method** — eliminates `instance_variable_get(:@events)`.
2. **Create `ModelSerializer`** — unify all serialization/deserialization into one class. Eliminates `respond_to?` chains and duplicated code.
3. **Fix `AttributeUpdater`** — remove `try_polymorphic_upgrade`'s `instance_variable_set/get`. Use proper factory pattern.
4. **Fix `CacheStore`** — use proper constructor/factory instead of `instance_variable_set`.
5. **Remove `respond_to?` from adapters** — call methods directly on `Adapter::Base` interface.
6. **Audit specs** — add specs that verify no `send`, no `instance_variable_get/set`, no `respond_to?` regressions.
