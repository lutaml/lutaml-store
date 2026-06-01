# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store, "custom serializer" do
  let(:custom_serializer) do
    Class.new do
      def serialize(model)
        { "identifier" => model.identifier, "value" => model.value }
      end

      def deserialize(data, _model_class)
        model = TestCustomModel.new
        model.identifier = data["identifier"]
        model.value = data["value"]
        model
      end
    end.new
  end

  before do
    stub_const("TestCustomModel", Class.new(Lutaml::Model::Serializable) do
      attribute :identifier, :string
      attribute :value, :string
      attribute :computed, :string

      def computed
        "#{identifier}-#{value}"
      end
    end)
  end

  it "uses custom serializer for save and fetch" do
    store = described_class.new(
      adapter: :memory,
      models: [
        { model: TestCustomModel, key: :identifier, serializer: custom_serializer }
      ]
    )

    model = TestCustomModel.new
    model.identifier = "abc"
    model.value = "hello"

    store.save(model)

    fetched = store.fetch(model: TestCustomModel, identifier: "abc")
    expect(fetched.identifier).to eq("abc")
    expect(fetched.value).to eq("hello")
    expect(fetched.computed).to eq("abc-hello")
  end

  it "uses custom serializer for all" do
    store = described_class.new(
      adapter: :memory,
      models: [
        { model: TestCustomModel, key: :identifier, serializer: custom_serializer }
      ]
    )

    3.times do |i|
      model = TestCustomModel.new
      model.identifier = "item-#{i}"
      model.value = "val-#{i}"
      store.save(model)
    end

    all_items = store.all(model: TestCustomModel)
    expect(all_items.size).to eq(3)
    expect(all_items.map(&:value).sort).to eq(%w[val-0 val-1 val-2])
  end

  it "uses custom serializer for update" do
    store = described_class.new(
      adapter: :memory,
      models: [
        { model: TestCustomModel, key: :identifier, serializer: custom_serializer }
      ]
    )

    model = TestCustomModel.new
    model.identifier = "xyz"
    model.value = "original"
    store.save(model)

    updated = store.update(
      model: TestCustomModel,
      identifier: "xyz",
      attributes: { "value" => "updated" }
    )
    expect(updated.value).to eq("updated")
  end

  it "falls back to default serialization when no custom serializer" do
    store = described_class.new(
      adapter: :memory,
      models: [{ model: TestCustomModel, key: :identifier }]
    )

    model = TestCustomModel.new
    model.identifier = "default"
    model.value = "normal"
    store.save(model)

    fetched = store.fetch(model: TestCustomModel, identifier: "default")
    expect(fetched.identifier).to eq("default")
  end
end
