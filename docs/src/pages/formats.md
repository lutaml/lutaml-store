---
layout: ../layouts/Docs.astro
title: Formats
---

# Formats

A **Format** handler defines how model entries serialize to and from files. All handlers inherit from `Format::Base` and are registered in `Format::FORMATS`, resolved via `Format.resolve(:symbol)`. Registering a new format never touches existing code.

| Symbol | Format | Multi-doc | Extension | Binary |
|---|---|---|---|---|
| `:yaml` | Single YAML document | no | `.yaml` | no |
| `:yamls` | YAML stream (multi-document) | yes | `.yaml` | no |
| `:json` | Single JSON document | no | `.json` | no |
| `:jsonl` | JSON Lines (one object per line) | yes | `.jsonl` | no |
| `:marshal` | Ruby Marshal | no | `.marshal` | yes |
| `:xml` | XML | yes | `.xml` | no |

## Handler interface

```ruby
class MyFormat < Lutaml::Store::Format::Base
  def serialize(models)  = ...
  def deserialize(data)  = ...
  def serialize_many(models) = ...   # multi-doc formats only
  def deserialize_many(data)  = ...  # multi-doc formats only
  def extension  = ".myfmt"
  def glob_pattern = "*.myfmt"
  def binary? = false
end

Lutaml::Store::Format.register(:myfmt, MyFormat)
```

## Choosing a format

- **`:yamls`** — human-editable multi-record files (the Glossarist pattern): one file per concept collection, streamed documents.
- **`:jsonl`** — append-heavy, line-oriented processing; one model per line.
- **`:marshal`** — fastest round-trip, Ruby-only, opaque to humans.
- **`:xml`** — interchange with XML-based pipelines; round-trips LutaML Model XML mappings.
- **`:json` / `:yaml`** — single-model files, configuration-style data.

## Usage with DatabaseStore

Pass `format:` per model registration:

```ruby
store = Lutaml::Store.new(
  adapter: { type: :filesystem, location: "./glossary" },
  models: [{ model: GlossaryTerm, key: :id, format: :yamls }]
)
```

`FormatSerializer` bridges the handler into the store's serializer interface, so CRUD operations transparently read and write the chosen format on disk.
