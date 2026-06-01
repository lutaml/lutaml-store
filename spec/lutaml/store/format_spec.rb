# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Lutaml::Store::Format do
  describe ".resolve" do
    it "resolves :yaml format" do
      fmt = described_class.resolve(:yaml)
      expect(fmt).to be_a(Lutaml::Store::Format::Yaml)
    end

    it "resolves :yamls format" do
      fmt = described_class.resolve(:yamls)
      expect(fmt).to be_a(Lutaml::Store::Format::Yamls)
    end

    it "resolves :json format" do
      fmt = described_class.resolve(:json)
      expect(fmt).to be_a(Lutaml::Store::Format::Json)
    end

    it "resolves :jsonl format" do
      fmt = described_class.resolve(:jsonl)
      expect(fmt).to be_a(Lutaml::Store::Format::Jsonl)
    end

    it "resolves :marshal format" do
      fmt = described_class.resolve(:marshal)
      expect(fmt).to be_a(Lutaml::Store::Format::MarshalFormat)
    end

    it "raises for unknown format" do
      expect { described_class.resolve(:unknown) }
        .to raise_error(Lutaml::Store::Format::UnsupportedFormatError)
    end
  end

  describe Lutaml::Store::Format::Yaml do
    let(:fmt) { described_class.new }

    it "returns .yaml extension" do
      expect(fmt.extension).to eq(".yaml")
    end

    it "returns glob pattern" do
      expect(fmt.glob_pattern).to eq("*.{yaml,yml}")
    end
  end

  describe Lutaml::Store::Format::Json do
    let(:fmt) { described_class.new }

    it "returns .json extension" do
      expect(fmt.extension).to eq(".json")
    end

    it "returns glob pattern" do
      expect(fmt.glob_pattern).to eq("*.json")
    end
  end

  describe Lutaml::Store::Format::MarshalFormat do
    let(:fmt) { described_class.new }

    it "returns .bin extension" do
      expect(fmt.extension).to eq(".bin")
    end
  end
end
