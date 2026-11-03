# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::JSON do
  describe ".parse and .generate" do
    it "round-trips plain Ruby structures with string keys" do
      value = { "a" => 1, "b" => [1, 2, { "c" => nil }], "d" => "text" }

      expect(described_class.parse(described_class.generate(value))).to eq(value)
    end

    it "symbolizes keys when symbolize_names is requested" do
      parsed = described_class.parse('{"a": {"b": [1, {"c": 2}]}}',
                                     symbolize_names: true)

      expect(parsed).to eq({ a: { b: [1, { c: 2 }] } })
    end

    it "keeps string keys by default" do
      expect(described_class.parse('{"a": 1}')).to eq({ "a" => 1 })
    end

    it "raises ParserError for malformed input" do
      expect { described_class.parse("{not json") }
        .to raise_error(Lutaml::Store::JSON::ParserError)
    end

    it "raises ParserError for non-string input" do
      expect { described_class.parse(nil) }
        .to raise_error(Lutaml::Store::JSON::ParserError)
    end

    it "raises GeneratorError for values outside the JSON type system" do
      expect { described_class.generate(Object.new) }
        .to raise_error(Lutaml::Store::JSON::GeneratorError)
    end
  end

  describe ".pretty_generate" do
    it "produces two-space-indented output" do
      expected = <<~JSON.delete_suffix("\n")
        {
          "a": [
            1,
            {
              "b": null
            }
          ]
        }
      JSON

      expect(described_class.pretty_generate({ "a" => [1, { "b" => nil }] }))
        .to eq(expected)
    end

    it "round-trips through parse" do
      value = { "name" => "test", "items" => %w[one two] }

      expect(described_class.parse(described_class.pretty_generate(value)))
        .to eq(value)
    end
  end
end
