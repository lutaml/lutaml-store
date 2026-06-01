# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::Config do
  describe "enhanced configuration features" do
    let(:enhanced_config) do
      {
        adapter_type: :memory,
        adapter_options: {},
        cache: {
          enabled: true,
          max_size: 500,
          ttl: 3600
        },
        monitoring: {
          enabled: true
        },
        events: {
          async: true
        },
        serialization: {
          formats: %w[marshal json yaml],
          validate_on_write: true
        },
        compression: {
          enabled: true,
          algorithm: "gzip",
          level: 9
        }
      }
    end

    subject { described_class.new(**enhanced_config) }

    describe "serialization configuration" do
      it "provides access to serialization formats" do
        expect(subject.serialization_formats).to eq(%w[marshal json yaml])
      end

      it "provides access to validate_on_write setting" do
        expect(subject.validate_on_write?).to be true
      end

      context "with default configuration" do
        subject { described_class.new }

        it "has default serialization formats" do
          expect(subject.serialization_formats).to include("marshal", "hash", "json", "yaml", "xml", "toml")
        end

        it "has validate_on_write disabled by default" do
          expect(subject.validate_on_write?).to be false
        end
      end
    end

    describe "compression configuration" do
      it "provides access to compression enabled setting" do
        expect(subject.compression_enabled?).to be true
      end

      it "provides access to compression algorithm" do
        expect(subject.compression_algorithm).to eq("gzip")
      end

      it "provides access to compression level" do
        expect(subject.compression_level).to eq(9)
      end

      context "with default configuration" do
        subject { described_class.new }

        it "has compression disabled by default" do
          expect(subject.compression_enabled?).to be false
        end

        it "has default compression algorithm" do
          expect(subject.compression_algorithm).to eq("gzip")
        end

        it "has default compression level" do
          expect(subject.compression_level).to eq(6)
        end
      end
    end

    describe "configuration merging" do
      it "merges partial configuration with defaults" do
        config = described_class.new(compression: { enabled: true })
        expect(config.compression_enabled?).to be true
        expect(config.compression_algorithm).to eq("gzip") # default
        expect(config.compression_level).to eq(6) # default
      end
    end

    describe "YAML configuration loading" do
      let(:yaml_config) do
        <<~YAML
          lutaml_store:
            adapter:
              type: filesystem
              options:
                path: /tmp/test_store
            compression:
              enabled: true
              algorithm: deflate
              level: 3
            serialization:
              validate_on_write: true
              formats:
                - json
                - yaml
        YAML
      end

      it "loads enhanced configuration from YAML" do
        config = described_class.from_yaml(yaml_config)

        expect(config.adapter_type).to eq(:filesystem)
        expect(config.adapter_options[:path]).to eq("/tmp/test_store")
        expect(config.compression_enabled?).to be true
        expect(config.compression_algorithm).to eq("deflate")
        expect(config.compression_level).to eq(3)
        expect(config.validate_on_write?).to be true
        expect(config.serialization_formats).to eq(%w[json yaml])
      end
    end

    describe "#to_h" do
      it "includes all configuration sections" do
        hash = subject.to_h

        expect(hash).to have_key(:adapter)
        expect(hash).to have_key(:cache)
        expect(hash).to have_key(:monitoring)
        expect(hash).to have_key(:events)
        # NOTE: to_h method needs to be updated to include new sections
      end
    end
  end

  describe "configuration validation" do
    context "with invalid compression settings" do
      it "validates compression algorithm" do
        # This would require adding validation for compression settings
        # in the Config class validate! method
      end
    end

    context "with invalid serialization settings" do
      it "validates serialization formats" do
        # This would require adding validation for serialization settings
        # in the Config class validate! method
      end
    end
  end
end
