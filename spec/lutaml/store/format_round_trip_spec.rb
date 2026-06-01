# frozen_string_literal: true

require "spec_helper"
require "json"

class FormatTestItem < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :value, :string
  attribute :count, :integer

  key_value do
    map :name, to: :name
    map :value, to: :value
    map :count, to: :count
  end
end

RSpec.describe "Format handler round-trips" do
  let(:item) { FormatTestItem.new(name: "alpha", value: "first", count: 42) }
  let(:items) do
    [
      FormatTestItem.new(name: "alpha", value: "first", count: 1),
      FormatTestItem.new(name: "beta", value: "second", count: 2)
    ]
  end

  shared_examples "single-model round-trip" do |format_sym|
    it "round-trips a single model through #{format_sym}" do
      fmt = Lutaml::Store::Format.resolve(format_sym)
      serialized = fmt.serialize(item)
      restored = fmt.deserialize(serialized, FormatTestItem)

      expect(restored.name).to eq("alpha")
      expect(restored.value).to eq("first")
      expect(restored.count).to eq(42)
    end
  end

  shared_examples "multi-model round-trip" do |format_sym|
    it "round-trips multiple models through #{format_sym}" do
      fmt = Lutaml::Store::Format.resolve(format_sym)
      serialized = fmt.serialize_many(items)
      restored = fmt.deserialize_many(serialized, FormatTestItem)

      expect(restored.size).to eq(2)
      expect(restored.map(&:name).sort).to eq(%w[alpha beta])
      expect(restored.map(&:count).sort).to eq([1, 2])
    end
  end

  describe Lutaml::Store::Format::Yaml do
    it_behaves_like "single-model round-trip", :yaml
    it_behaves_like "multi-model round-trip", :yaml

    it "produces valid YAML" do
      fmt = described_class.new
      output = fmt.serialize(item)
      expect(output).to include("name:")
      expect(output).to include("value:")
    end
  end

  describe Lutaml::Store::Format::Yamls do
    it_behaves_like "single-model round-trip", :yamls
    it_behaves_like "multi-model round-trip", :yamls

    it "produces multi-document YAML stream" do
      fmt = described_class.new
      output = fmt.serialize_many(items)
      expect(output.scan(/^---/).size).to be >= 2
    end
  end

  describe Lutaml::Store::Format::Json do
    it_behaves_like "single-model round-trip", :json

    it "produces valid JSON" do
      fmt = described_class.new
      output = fmt.serialize(item)
      parsed = JSON.parse(output)
      expect(parsed["name"]).to eq("alpha")
      expect(parsed["count"]).to eq(42)
    end
  end

  describe Lutaml::Store::Format::Jsonl do
    it_behaves_like "single-model round-trip", :jsonl
    it_behaves_like "multi-model round-trip", :jsonl

    it "produces line-delimited JSON" do
      fmt = described_class.new
      output = fmt.serialize_many(items)
      lines = output.lines.reject { |l| l.strip.empty? }
      expect(lines.size).to eq(2)
      lines.each { |line| expect { JSON.parse(line) }.not_to raise_error }
    end
  end

  describe Lutaml::Store::Format::MarshalFormat do
    it_behaves_like "single-model round-trip", :marshal
    it_behaves_like "multi-model round-trip", :marshal

    it "produces binary data" do
      fmt = described_class.new
      output = fmt.serialize(item)
      expect(output).to be_a(String)
      expect(output.encoding).to eq(Encoding::ASCII_8BIT)
    end
  end
end
