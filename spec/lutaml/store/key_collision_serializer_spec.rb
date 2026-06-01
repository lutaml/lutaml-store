# frozen_string_literal: true

require "spec_helper"

# Model with a key collision: both id and code serialize to the same "id" key.
# Demonstrates the custom serializer pattern for preserving all fields.
class CollisionItem < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :code, :string
  attribute :label, :string

  key_value do
    map :id, to: :id
    map :code, with: { to: :code_to_yaml, from: :code_from_yaml }
    map :label, to: :label
  end

  def code_to_yaml(model, doc)
    doc["id"] = model.code if model.code
  end

  def code_from_yaml(model, value)
    model.code = value if value
  end
end

class CollisionSerializer < Lutaml::Store::ModelSerializer
  def serialize(model, _registration = nil)
    {
      "_yaml" => model.to_yaml,
      "_id" => model.id,
      "_code" => model.code
    }
  end

  def deserialize(data, expected_class, _registration = nil)
    model = expected_class.from_yaml(data["_yaml"])
    model.id = data["_id"]
    model.code = data["_code"]
    model
  end
end

RSpec.describe "Custom serializer with key collision workaround" do
  let(:store) do
    Lutaml::Store.new(
      adapter: :memory,
      models: [{
        model: CollisionItem,
        key: :id,
        serializer: CollisionSerializer.new
      }]
    )
  end

  it "preserves both id and code through save/fetch" do
    item = CollisionItem.new(id: "item-1", code: "CODE-1", label: "First item")
    store.save(item)

    fetched = store.fetch(model: CollisionItem, id: "item-1")
    expect(fetched.id).to eq("item-1")
    expect(fetched.code).to eq("CODE-1")
    expect(fetched.label).to eq("First item")
  end

  it "preserves fields through update" do
    item = CollisionItem.new(id: "item-2", code: "CODE-2", label: "Original")
    store.save(item)

    updated = store.update(model: CollisionItem, id: "item-2", attributes: { label: "Updated" })
    expect(updated.id).to eq("item-2")
    expect(updated.code).to eq("CODE-2")
    expect(updated.label).to eq("Updated")
  end

  it "preserves fields through where query" do
    store.save(CollisionItem.new(id: "a1", code: "C1", label: "One"))
    store.save(CollisionItem.new(id: "a2", code: "C2", label: "Two"))

    found = store.where(model: CollisionItem, code: "C1")
    expect(found.size).to eq(1)
    expect(found.first.id).to eq("a1")
    expect(found.first.code).to eq("C1")
  end

  it "lists all items with correct fields" do
    3.times do |i|
      store.save(CollisionItem.new(id: "x-#{i}", code: "C-#{i}", label: "Item #{i}"))
    end

    all = store.all(model: CollisionItem)
    expect(all.size).to eq(3)
    all.each do |item|
      expect(item.id).to start_with("x-")
      expect(item.code).to start_with("C-")
    end
  end
end
