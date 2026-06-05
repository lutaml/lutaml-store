# frozen_string_literal: true

require "spec_helper"
require "support/yamls_test_model"

RSpec.describe Lutaml::Store::Format::Yamls do
  let(:fmt) { described_class.new }

  let(:model) do
    YamlsTestModel.new(
      header: YamlsTestHeader.new(id: "test-1", name: "Test"),
      parts: [
        YamlsTestPart.new(label: "a", value: "1"),
        YamlsTestPart.new(label: "b", value: "2")
      ]
    )
  end

  describe "#extension" do
    it { expect(fmt.extension).to eq(".yaml") }
  end

  describe "#glob_pattern" do
    it { expect(fmt.glob_pattern).to eq("*.{yaml,yml}") }
  end

  describe "#serialize" do
    it "produces a YAML stream starting with ---" do
      result = fmt.serialize(model)
      expect(result).to start_with("---")
    end

    it "produces multiple --- separators for multi-part models" do
      result = fmt.serialize(model)
      separators = result.scan(/^---$/).length
      expect(separators).to be >= 2
    end
  end

  describe "#deserialize" do
    it "reconstructs the model from a YAML stream" do
      yaml = fmt.serialize(model)
      loaded = fmt.deserialize(yaml, YamlsTestModel)

      expect(loaded.header.id).to eq("test-1")
      expect(loaded.header.name).to eq("Test")
    end
  end

  describe "round-trip" do
    it "preserves model data including parts" do
      yaml = fmt.serialize(model)
      loaded = fmt.deserialize(yaml, YamlsTestModel)

      expect(loaded.header.id).to eq("test-1")
      expect(loaded.header.name).to eq("Test")
      expect(loaded.parts.length).to eq(2)
      expect(loaded.parts.first.label).to eq("a")
      expect(loaded.parts.last.value).to eq("2")
    end
  end

  describe "#serialize_many" do
    it "serializes a single model identically to #serialize" do
      result = fmt.serialize_many([model])
      expect(result).to eq(fmt.serialize(model))
    end

    it "separates models with newline to prevent data corruption" do
      model2 = YamlsTestModel.new(
        header: YamlsTestHeader.new(id: "test-2", name: "Second"),
        parts: [YamlsTestPart.new(label: "c", value: "3")]
      )
      result = fmt.serialize_many([model, model2])
      # Each model's stream ends before the next one starts
      expect(result).to match(/value: '2'\n---\nid: test-2/)
    end

    it "produces output with proper document boundaries for single model" do
      result = fmt.serialize_many([model])
      loaded = fmt.deserialize_many(result, YamlsTestModel)
      expect(loaded.size).to eq(1)
      expect(loaded.first.header.id).to eq("test-1")
    end
  end

  describe "#deserialize_many" do
    it "returns an array from a YAML stream" do
      yaml = fmt.serialize(model)
      result = fmt.deserialize_many(yaml, YamlsTestModel)
      expect(result).to be_an(Array)
      expect(result.first).to be_a(YamlsTestModel)
    end
  end
end
